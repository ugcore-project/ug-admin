/*

    ug-admin - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// What the panel shows for each action: where it sits, which fields it asks for, and whether it needs a second click.

import { Action, type ActionArgs } from "@/types/protocol";

export const Field = {
  Reason: "reason",
  Duration: "duration",
  Account: "account",
  Amount: "amount",
  Job: "job",
  Gang: "gang",
  Grade: "grade",
  Item: "item",
  Count: "count",
  Group: "group",
  Text: "text",
  Model: "model",
  Identifier: "identifier",
  Minutes: "minutes",
  Location: "location",
} as const;

export type Field = (typeof Field)[keyof typeof Field];

export const ActionGroup = {
  Move: "move",
  Care: "care",
  Discipline: "discipline",
  Character: "character",
  Staff: "staff",
} as const;

export type ActionGroup = (typeof ActionGroup)[keyof typeof ActionGroup];

export interface ActionSpec {
  action: Action;
  fields: Field[];
  /** Fields that MAY stay empty. */
  optional?: Field[];
  /** Asks for a second click before it runs. */
  confirm?: boolean;
  danger?: boolean;
}

/** Actions on a selected player, by group, in display order. */
export const PLAYER_ACTIONS: Record<ActionGroup, ActionSpec[]> = {
  [ActionGroup.Move]: [
    { action: Action.Goto, fields: [] },
    { action: Action.Bring, fields: [] },
    { action: Action.Spectate, fields: [] },
    { action: Action.Back, fields: [] },
    { action: Action.SendTo, fields: [Field.Location] },
  ],
  [ActionGroup.Care]: [
    { action: Action.Revive, fields: [] },
    { action: Action.Heal, fields: [] },
    { action: Action.Fix, fields: [] },
  ],
  [ActionGroup.Discipline]: [
    { action: Action.Freeze, fields: [] },
    { action: Action.Message, fields: [Field.Text] },
    { action: Action.Warn, fields: [Field.Reason] },
    { action: Action.Mute, fields: [Field.Minutes, Field.Reason], optional: [Field.Reason] },
    { action: Action.Jail, fields: [Field.Minutes, Field.Reason], optional: [Field.Reason], danger: true },
    { action: Action.Kick, fields: [Field.Reason], confirm: true, danger: true },
    { action: Action.Ban, fields: [Field.Duration, Field.Reason], confirm: true, danger: true },
    { action: Action.Kill, fields: [], confirm: true, danger: true },
  ],
  [ActionGroup.Character]: [
    { action: Action.GiveMoney, fields: [Field.Account, Field.Amount] },
    { action: Action.SetMoney, fields: [Field.Account, Field.Amount] },
    { action: Action.SetJob, fields: [Field.Job, Field.Grade] },
    { action: Action.SetGang, fields: [Field.Gang, Field.Grade] },
    { action: Action.GiveItem, fields: [Field.Item, Field.Count] },
    { action: Action.OpenInventory, fields: [] },
    { action: Action.ClearInventory, fields: [], confirm: true, danger: true },
  ],
  [ActionGroup.Staff]: [
    { action: Action.SetGroup, fields: [Field.Group] },
    { action: Action.RemoveGroup, fields: [Field.Group], confirm: true },
  ],
};

/** Self actions of the quick bar that run on one click. */
export const QUICK_TOGGLES: Action[] = [
  Action.Duty,
  Action.Noclip,
  Action.Vision,
  Action.God,
  Action.Invisible,
  Action.Waypoint,
  Action.Back,
  Action.Fix,
  Action.DeleteVehicle,
];

/** Quick bar tools that ask for one value first. */
export const QUICK_TOOLS: ActionSpec[] = [
  { action: Action.Car, fields: [Field.Model] },
  { action: Action.Announce, fields: [Field.Text] },
  { action: Action.Unban, fields: [Field.Identifier] },
];

/** Actions on every player at once. Each asks for a second click. */
export const BULK_ACTIONS: ActionSpec[] = [
  { action: Action.ReviveAll, fields: [], confirm: true },
  { action: Action.BringAll, fields: [], confirm: true },
  { action: Action.FreezeAll, fields: [], confirm: true, danger: true },
];

/** Everything the quick bar MAY show, in its default order: modes and teleports first, then tools. */
export const QUICK_ITEMS: Action[] = [...QUICK_TOGGLES, ...QUICK_TOOLS.map((spec) => spec.action)];

/** Quick bar actions in the staff member's order. Actions the order leaves out keep their default place after it. */
export function orderQuick(items: Action[], order: Action[]): Action[] {
  const rank = new Map(order.map((action, index) => [action, index]));
  const place = (action: Action) => rank.get(action) ?? order.length + items.indexOf(action);

  return [...items].sort((a, b) => place(a) - place(b));
}

export type FormValues = Partial<Record<Field, string>>;

const INTEGER = /^-?\d{1,9}$/;

/** Turns form values into action arguments. Returns null when a required field is missing or malformed. */
export function buildArgs(fields: Field[], values: FormValues, optional: Field[] = []): ActionArgs | null {
  const args: ActionArgs = {};

  for (const field of fields) {
    const value = (values[field] ?? "").trim();

    if (value === "") {
      // A grade MAY be left out: the server uses the lowest one.
      if (field === Field.Grade || optional.includes(field)) {
        continue;
      }

      return null;
    }

    switch (field) {
      case Field.Amount:
      case Field.Count:
      case Field.Minutes:
      case Field.Grade: {
        if (!INTEGER.test(value)) {
          return null;
        }

        args[field] = Number(value);
        break;
      }

      // Jobs and gangs share the `job` argument.
      case Field.Gang:
        args.job = value;
        break;

      default:
        args[field] = value;
    }
  }

  return args;
}
