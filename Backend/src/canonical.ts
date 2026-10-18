/** Stable serialization prevents dictionary order changes from resetting alert baselines. */
export function canonicalJSON(value: unknown): string {
  if (value == null || typeof value !== "object") return JSON.stringify(value) ?? "null";
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  const object = value as Record<string,unknown>;
  return `{${Object.keys(object).filter(key=>object[key] !== undefined).sort().map(key=>`${JSON.stringify(key)}:${canonicalJSON(object[key])}`).join(",")}}`;
}
