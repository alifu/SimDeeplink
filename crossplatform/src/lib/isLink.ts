/** A single URL with a scheme, custom app schemes included. Same rule as the Rust side (`api/url.rs`). */
export function isLink(text: string): boolean {
  if (/\s/.test(text)) return false;
  const colon = text.indexOf(":");
  if (colon < 0) return false;
  const scheme = text.slice(0, colon);
  if (!/^[A-Za-z][A-Za-z0-9+.-]*$/.test(scheme)) return false;
  const rest = text.slice(colon + 1);
  return (rest.startsWith("//") ? rest.slice(2) : rest).length > 0;
}
