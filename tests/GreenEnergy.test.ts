
import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;

describe("GreenEnergy Contract Tests", () => {
  it("ensures simnet is well initialized", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("can get total credits", () => {
    const { result } = simnet.callReadOnlyFn("GreenEnergy", "get-total-credits", [], address1);
    expect(result).toBeUint(0);
  });
});
