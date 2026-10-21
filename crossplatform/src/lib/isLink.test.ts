import { describe, expect, it } from "vitest";

import { isLink } from "./isLink";

describe("isLink", () => {
  it.each(["https://example.com/a?b=1&c=2", "myapp://path?id=1", "tel:+62812"])("accepts %s", (link) => {
    expect(isLink(link)).toBe(true);
  });

  it.each(["", "example.com", "https://", "myapp:", "my app://x", "1app://x", "://x"])("rejects %j", (text) => {
    expect(isLink(text)).toBe(false);
  });
});
