import { describe, expect, test } from "bun:test";
import { locateEvidence, pageAt } from "./evidence-locate.ts";

const TEXT =
  "\n--- pagina 1 ---\n" +
  "Funderingsonderzoek   Wilhelminakade 59\n\n" +
  "Opdrachtgever:      Woonstad Rotterdam\n" +
  "\n--- pagina 2 ---\n" +
  "Tabel 3: bouwjaar | Wilhelminakade 59 | 1910\n" +
  "De fundering bestaat uit houten palen met een betonnen oplanger.\n" +
  "\n--- pagina 3 ---\n" +
  "Conclusie: de kwaliteit van de fundering is matig tot slecht.\n" +
  "Handhavingstermijn: 10 jaar.\n";

describe("locateEvidence", () => {
  test("exact quote on the page it sits on", () => {
    const loc = locateEvidence("Handhavingstermijn: 10 jaar.", TEXT)!;
    expect(loc.page).toBe(3);
    expect(TEXT.slice(loc.offset, loc.offset + 18)).toBe("Handhavingstermijn");
  });

  test("case and whitespace are folded (layout output pads columns)", () => {
    const loc = locateEvidence("funderingsonderzoek wilhelminakade 59", TEXT)!;
    expect(loc.page).toBe(1);
  });

  test("a paraphrased tail still matches on its prefix", () => {
    const loc = locateEvidence("De fundering bestaat uit houten palen, betonoplanger aanwezig", TEXT)!;
    expect(loc.page).toBe(2);
    expect(TEXT.slice(loc.offset, loc.offset + 12)).toBe("De fundering");
  });

  test("order follows the text, not the field name", () => {
    const bouwjaar = locateEvidence("Tabel 3: bouwjaar | Wilhelminakade 59 | 1910", TEXT)!;
    const kwaliteit = locateEvidence("de kwaliteit van de fundering is matig tot slecht", TEXT)!;
    const opdrachtgever = locateEvidence("Opdrachtgever: Woonstad Rotterdam", TEXT)!;
    expect(opdrachtgever.offset).toBeLessThan(bouwjaar.offset);
    expect(bouwjaar.offset).toBeLessThan(kwaliteit.offset);
  });

  test("the pipeline's own prefixes and quotes are stripped", () => {
    expect(locateEvidence("afgeleid: “Handhavingstermijn: 10 jaar.”", TEXT)?.page).toBe(3);
  });

  test("too short to trust is null, not a guess", () => {
    expect(locateEvidence("1910", TEXT)).toBeNull();
    expect(locateEvidence("", TEXT)).toBeNull();
    expect(locateEvidence(null, TEXT)).toBeNull();
  });

  test("absent quote is null", () => {
    expect(locateEvidence("Deze zin staat nergens in het rapport", TEXT)).toBeNull();
  });

  test("a locator prefix around a quoted passage (\"pagina 2, paragraaf 1.1: '…'\")", () => {
    const loc = locateEvidence("pagina 2, paragraaf 3.1: 'De fundering bestaat uit houten palen'", TEXT)!;
    expect(loc.page).toBe(2);
    expect(TEXT.slice(loc.offset, loc.offset + 12)).toBe("De fundering");
  });

  test("value -- table reference: the passage after the dash", () => {
    const loc = locateEvidence("matig tot slecht -- Conclusie: de kwaliteit van de fundering is matig tot slecht", TEXT)!;
    expect(loc.page).toBe(3);
  });

  test("a named page pins the page when the passage itself is not found", () => {
    const loc = locateEvidence("pagina 3, tabel 9: 'Deze tabel staat niet in de tekstlaag'", TEXT)!;
    expect(loc.page).toBe(3);
    expect(loc.offset).toBe(TEXT.indexOf("\n--- pagina 3 ---"));
  });

  test("a named page that the text does not have stays null", () => {
    expect(locateEvidence("pagina 40: 'niet aanwezig in deze tekst'", TEXT)).toBeNull();
  });

  test("text without page markers gives an offset but no page", () => {
    const loc = locateEvidence("houten palen met een betonnen oplanger", "De fundering: houten palen met een betonnen oplanger.")!;
    expect(loc.page).toBeNull();
    expect(loc.offset).toBe(14);
  });
});

describe("pageAt", () => {
  test("before the first marker is null; after each marker its page", () => {
    expect(pageAt(TEXT, 0)).toBeNull();
    expect(pageAt(TEXT, TEXT.indexOf("Opdrachtgever"))).toBe(1);
    expect(pageAt(TEXT, TEXT.indexOf("Conclusie"))).toBe(3);
  });
});
