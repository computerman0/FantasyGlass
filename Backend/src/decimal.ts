/** Exact base-10 arithmetic for scores. Never use JavaScript floating point for fantasy totals. */
export class Decimal {
  constructor(readonly coefficient: bigint, readonly scale: number) {}
  static parse(input: unknown): Decimal {
    const text = String(input ?? "0");
    const m = /^([+-]?)(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(text);
    if (!m || text.length > 512) throw new Error("Invalid decimal");
    const exponent = Number(m[4] ?? 0);
    if (!Number.isSafeInteger(exponent) || Math.abs(exponent) > 256) throw new Error("Decimal exponent out of range");
    const fractional = m[3] ?? "";
    const coefficient = BigInt(`${m[1] === "-" ? "-" : ""}${m[2]}${fractional}`);
    const scale = fractional.length - exponent;
    return scale < 0 ? new Decimal(coefficient * 10n ** BigInt(-scale), 0) : new Decimal(coefficient, scale);
  }
  add(other: Decimal): Decimal {
    const scale = Math.max(this.scale, other.scale);
    return new Decimal(this.coefficient * 10n ** BigInt(scale-this.scale) + other.coefficient * 10n ** BigInt(scale-other.scale), scale);
  }
  multiply(other: Decimal): Decimal { return new Decimal(this.coefficient * other.coefficient, this.scale+other.scale); }
  subtract(other: Decimal): Decimal { return this.add(new Decimal(-other.coefficient, other.scale)); }
  compare(other: Decimal): number { const n = this.subtract(other).coefficient; return n === 0n ? 0 : n > 0n ? 1 : -1; }
  wholeDivide(other: Decimal): Decimal {
    if (other.coefficient <= 0n) throw new Error("Whole-unit size must be positive");
    return new Decimal(this.coefficient * 10n ** BigInt(other.scale) / (other.coefficient * 10n ** BigInt(this.scale)), 0);
  }
  toString(): string {
    const negative = this.coefficient < 0n;
    let digits = (negative ? -this.coefficient : this.coefficient).toString().padStart(this.scale+1,"0");
    if (this.scale) digits = `${digits.slice(0,-this.scale)}.${digits.slice(-this.scale)}`.replace(/0+$/,"").replace(/\.$/,"");
    return (negative && digits !== "0" ? "-" : "") + digits;
  }
}
export const d = (value: unknown): Decimal => Decimal.parse(value);

/** Preserve numeric token spellings in provider JSON before JSON.parse could coerce them to doubles. */
export function parseProviderJSON(text: string): unknown {
  let result = "", quoted = false, escaped = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i]!;
    if (quoted) {
      result += char;
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === '"') quoted = false;
    } else if (char === '"') { quoted = true; result += char; }
    else if (char === "-" || /[0-9]/.test(char)) {
      const token = /^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/.exec(text.slice(i))?.[0];
      if (!token) throw new Error("Malformed JSON number");
      result += JSON.stringify(token); i += token.length-1;
    } else result += char;
  }
  return JSON.parse(result);
}
