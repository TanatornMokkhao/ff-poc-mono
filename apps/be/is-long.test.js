import { test } from "node:test";
import { isLong } from "./notes.js";

test("isLong runs", () => {
  isLong("a long piece of text");
});
