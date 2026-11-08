#!/usr/bin/env python3
"""Writes and signs the "Rootine Screen Time" shortcut (DATA.md section 1).

    scripts/make-screen-time-shortcut.py            -> build/Shortcuts/Rootine Screen Time.shortcut

The shortcut logs yesterday's and today's app and website activity into Rootine. Signing runs
`shortcuts sign --mode anyone` and needs a Mac signed in to iCloud. Automations can't be imported, so they
are set up by hand (DATA.md, "Setting it up on the iPhone").

Action encoding, checked against the iOS 26.3 simulator runtime:
- Get App & Website Activity is `CalculateAppUsageIntent` in the system App Intents extension
  `com.apple.intelligenceplatform...IntelligencePlatformDataActionsAppIntentsExtension`. System extension
  actions are written as `<extension bundle ID>.<intent>`, with enum choices as plain strings (the same shape
  as Writing Tools' summarize action in the Shortcuts gallery). `during`: today / yesterday / ...;
  `activityType`: all / app / website. Leaving out `selectedDevice` means this device.
- Rootine's action is `com.danfoygel.rootine.LogScreenTimeIntent`, with an `AppIntentDescriptor`.
- Its inputs are the activity lists' Description property (a `WFPropertyVariableAggrandizement` whose
  `PropertyUserInfo` names the App Intents entity property `description`; key names from WorkflowKit).
"""

import plistlib
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "build" / "Shortcuts"
NAME = "Rootine Screen Time"

SCREEN_TIME = (
    "com.apple.intelligenceplatform.IntelligencePlatform."
    "IntelligencePlatformDataActionsAppIntentsExtension.CalculateAppUsageIntent"
)
ROOTINE = {
    "AppIntentIdentifier": "LogScreenTimeIntent",
    "BundleIdentifier": "com.danfoygel.rootine",
    "Name": "Rootine",
    "TeamIdentifier": "ZVU48K8YCD",
    "ActionRequiresAppInstallation": True,
}
ACTIVITY_OUTPUT = "App & Website Activity"


def stable_uuid(name: str) -> str:
    """The same UUIDs on every run, so the generated file only changes when the shortcut does."""
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"rootine/screen-time-shortcut/{name}")).upper()


def token(attachment: dict) -> dict:
    """A text field holding one variable."""
    return {
        "Value": {"attachmentsByRange": {"{0, 1}": attachment}, "string": "￼"},
        "WFSerializationType": "WFTextTokenString",
    }


def descriptions_of(action_uuid: str) -> dict:
    """The activity list's Description property: one `Name (1h 35m)` per item. The list itself turns into
    other text that has no durations (Dan's first run, 2026-11-07: "18 rows had no name or duration")."""
    return token({
        "OutputName": ACTIVITY_OUTPUT,
        "OutputUUID": action_uuid,
        "Type": "ActionOutput",
        "Aggrandizements": [{
            "Type": "WFPropertyVariableAggrandizement",
            "PropertyName": "Description",
            "PropertyUserInfo": {"WFLinkEntityContentPropertyUserInfoPropertyIdentifier": "description"},
        }],
    })


def comment(text: str) -> dict:
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.comment",
        "WFWorkflowActionParameters": {"UUID": stable_uuid(text), "WFCommentActionText": text},
    }


def activity(during: str, activity_type: str) -> tuple[dict, str]:
    action_uuid = stable_uuid(f"activity-{during}-{activity_type}")
    action = {
        "WFWorkflowActionIdentifier": SCREEN_TIME,
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "during": during,
            "activityType": activity_type,
        },
    }
    return action, action_uuid


def log(day: str, apps_uuid: str, websites_uuid: str) -> dict:
    parameters = {
        "UUID": stable_uuid(f"log-{day}"),
        "AppIntentDescriptor": ROOTINE,
        "apps": descriptions_of(apps_uuid),
        "websites": descriptions_of(websites_uuid),
    }
    if day == "today":
        parameters["day"] = token({"Type": "CurrentDate"})
    # Yesterday leaves Day empty: the intent's default.
    return {
        "WFWorkflowActionIdentifier": "com.danfoygel.rootine.LogScreenTimeIntent",
        "WFWorkflowActionParameters": parameters,
    }


def workflow() -> dict:
    actions = [
        comment(
            "Logs yesterday's and today's Screen Time into Rootine. Run by automations: 06:00, "
            "when Rootine opens, and when the apps you limit close (DATA.md, section 1)."
        )
    ]
    for day in ("yesterday", "today"):
        apps, apps_uuid = activity(day, "app")
        websites, websites_uuid = activity(day, "website")
        actions += [apps, websites, log(day, apps_uuid, websites_uuid)]
    return {
        "WFQuickActionSurfaces": [],
        "WFWorkflowActions": actions,
        "WFWorkflowClientVersion": "4018.0.4",
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowIcon": {
            # Hourglass on indigo.
            "WFWorkflowIconGlyphNumber": 59511,
            "WFWorkflowIconStartColor": 1440408063,
        },
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": [],
    }


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    unsigned = OUT_DIR / f"{NAME} (unsigned).shortcut"
    signed = OUT_DIR / f"{NAME}.shortcut"
    with unsigned.open("wb") as file:
        plistlib.dump(workflow(), file, fmt=plistlib.FMT_BINARY)
    result = subprocess.run(
        ["shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(signed)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stdout + result.stderr, file=sys.stderr)
        return result.returncode
    print(signed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
