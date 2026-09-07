import { describe, expect, test } from "bun:test";
import { normaliseDocumentDate } from "./util.ts";

/**
 * What Dutch reports print on the cover, and what the model hands back
 * despite being asked for ISO. A year outside 1900..next year is a misread.
 */
describe("normaliseDocumentDate", () => {
  test.each<[string, string | null]>([
    ["2021-03-12", "2021-03-12"],
    ["2021-03-12T00:00:00", "2021-03-12"],
    ["12-03-2021", "2021-03-12"],
    ["12/3/2021", "2021-03-12"],
    ["12 maart 2021", "2021-03-12"],
    ["Maart 2021", "2021-03-01"],
    ["1 sept. 2019", "2019-09-01"],
    ["2021-03", "2021-03-01"],
    ["2021", "2021-01-01"],
    ["31-02-2021", null],
    ["1850-01-01", null],
    ["2099-01-01", null],
    ["onbekend", null],
    ["12 foo 2021", null],
  ])("%s -> %s", (input, want) => {
    expect(normaliseDocumentDate(input)).toBe(want);
  });
});
