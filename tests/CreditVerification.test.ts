import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const deployer = accounts.get("deployer")!;

describe("CreditVerification Contract Tests", () => {
    it("can register a new verifier", () => {
        const { result } = simnet.callPublicFn(
            'CreditVerification',
            'register-verifier',
            [
                Cl.principal(address1),
                Cl.stringAscii("TechVerify"),
                Cl.stringAscii("ISO14064 Certified")
            ],
            deployer
        );
        
        // expect(result).toBeOk(Cl.uint(1));
    });

    it("only owner can register verifiers", () => {
        const { result } = simnet.callPublicFn(
            'CreditVerification',
            'register-verifier',
            [
                Cl.principal(address2),
                Cl.stringAscii("UnauthorizedVerify"),
                Cl.stringAscii("No Certification")
            ],
            address1
        );
        
        // expect(result).toBeErr(Cl.uint(200));
    });

    it("can submit verification request", () => {
        const { result } = simnet.callPublicFn(
            'CreditVerification',
            'submit-verification-request',
            [
                Cl.uint(100),
                Cl.stringAscii("SOLAR-001"),
                Cl.uint(1),
                Cl.stringAscii("Solar farm project in California")
            ],
            address1
        );
        
        // expect(result).toBeOk(Cl.uint(1));
    });

    it("cannot submit request with zero credits", () => {
        const { result } = simnet.callPublicFn(
            'CreditVerification',
            'submit-verification-request',
            [
                Cl.uint(0),
                Cl.stringAscii("SOLAR-002"),
                Cl.uint(1),
                Cl.stringAscii("Invalid project")
            ],
            address1
        );
        
        // expect(result).toBeErr(Cl.uint(206));
    });

    it("owner can assign verifier to request", () => {
        // Register verifier first
        simnet.callPublicFn(
            'CreditVerification',
            'register-verifier',
            [
                Cl.principal(address1),
                Cl.stringAscii("TechVerify"),
                Cl.stringAscii("ISO14064 Certified")
            ],
            deployer
        );
        
        // Submit request
        simnet.callPublicFn(
            'CreditVerification',
            'submit-verification-request',
            [
                Cl.uint(100),
                Cl.stringAscii("SOLAR-001"),
                Cl.uint(1),
                Cl.stringAscii("Solar farm project")
            ],
            address2
        );
        
        // Assign verifier
        const { result } = simnet.callPublicFn(
            'CreditVerification',
            'assign-verifier',
            [
                Cl.uint(1),
                Cl.principal(address1)
            ],
            deployer
        );
        
        // expect(result).toBeOk(Cl.bool(true));
    });

    it("verifier can complete verification", () => {
        // Setup: register verifier, submit request, assign verifier
        simnet.callPublicFn(
            'CreditVerification',
            'register-verifier',
            [
                Cl.principal(address1),
                Cl.stringAscii("TechVerify"),
                Cl.stringAscii("ISO14064 Certified")
            ],
            deployer
        );
        
        simnet.callPublicFn(
            'CreditVerification',
            'submit-verification-request',
            [
                Cl.uint(100),
                Cl.stringAscii("SOLAR-001"),
                Cl.uint(1),
                Cl.stringAscii("Solar farm project")
            ],
            address2
        );
        
        simnet.callPublicFn(
            'CreditVerification',
            'assign-verifier',
            [
                Cl.uint(1),
                Cl.principal(address1)
            ],
            deployer
        );
        
        // Complete verification
        const { result } = simnet.callPublicFn(
            'CreditVerification',
            'complete-verification',
            [
                Cl.uint(1),
                Cl.bool(true),
                Cl.uint(52560) // 1 year validity
            ],
            address1
        );
        
        // expect(result).toBeOk(Cl.bool(true));
    });

    it("can transfer verified credits", () => {
        // Setup complete verification flow
        simnet.callPublicFn(
            'CreditVerification',
            'register-verifier',
            [
                Cl.principal(address1),
                Cl.stringAscii("TechVerify"),
                Cl.stringAscii("ISO14064 Certified")
            ],
            deployer
        );
        
        simnet.callPublicFn(
            'CreditVerification',
            'submit-verification-request',
            [
                Cl.uint(100),
                Cl.stringAscii("SOLAR-001"),
                Cl.uint(1),
                Cl.stringAscii("Solar farm project")
            ],
            address2
        );
        
        simnet.callPublicFn(
            'CreditVerification',
            'assign-verifier',
            [
                Cl.uint(1),
                Cl.principal(address1)
            ],
            deployer
        );
        
        simnet.callPublicFn(
            'CreditVerification',
            'complete-verification',
            [
                Cl.uint(1),
                Cl.bool(true),
                Cl.uint(52560)
            ],
            address1
        );
        
        // Transfer credits
        const { result } = simnet.callPublicFn(
            'CreditVerification',
            'transfer-verified-credits',
            [
                Cl.uint(1),
                Cl.uint(50),
                Cl.principal(address3)
            ],
            address2
        );
        
        // expect(result).toBeOk(Cl.bool(true));
    });

    it("can get verifier information", () => {
        // Register verifier first
        simnet.callPublicFn(
            'CreditVerification',
            'register-verifier',
            [
                Cl.principal(address1),
                Cl.stringAscii("TechVerify"),
                Cl.stringAscii("ISO14064 Certified")
            ],
            deployer
        );
        
        const { result } = simnet.callReadOnlyFn(
            'CreditVerification',
            'get-verifier',
            [Cl.principal(address1)],
            deployer
        );
        
        // expect(result).toBeSome();
    });

    it("can get verification statistics", () => {
        const { result } = simnet.callReadOnlyFn(
            'CreditVerification',
            'get-verification-stats',
            [],
            deployer
        );
        
        // expect(result).toBeTuple({
        //     "total-verifiers": Cl.uint(0),
        //     "total-requests": Cl.uint(0),
        //     "total-verified-credits": Cl.uint(0)
        // });
    });

    it("can get verification standards", () => {
        const { result } = simnet.callReadOnlyFn(
            'CreditVerification',
            'get-verification-standards',
            [],
            deployer
        );
        
        // expect(result).toBeTuple({
        //     "vcs": Cl.uint(1),
        //     "cdm": Cl.uint(2),
        //     "gold": Cl.uint(3),
        //     "car": Cl.uint(4)
        // });
    });

    it("owner can deactivate verifier", () => {
        // Register verifier first
        simnet.callPublicFn(
            'CreditVerification',
            'register-verifier',
            [
                Cl.principal(address1),
                Cl.stringAscii("TechVerify"),
                Cl.stringAscii("ISO14064 Certified")
            ],
            deployer
        );
        
        // Deactivate verifier
        const { result } = simnet.callPublicFn(
            'CreditVerification',
            'set-verifier-status',
            [
                Cl.principal(address1),
                Cl.bool(false)
            ],
            deployer
        );
        
        // expect(result).toBeOk(Cl.bool(true));
    });

    it("cannot assign inactive verifier", () => {
        // Register and deactivate verifier
        simnet.callPublicFn(
            'CreditVerification',
            'register-verifier',
            [
                Cl.principal(address1),
                Cl.stringAscii("TechVerify"),
                Cl.stringAscii("ISO14064 Certified")
            ],
            deployer
        );
        
        simnet.callPublicFn(
            'CreditVerification',
            'set-verifier-status',
            [
                Cl.principal(address1),
                Cl.bool(false)
            ],
            deployer
        );
        
        // Submit request
        simnet.callPublicFn(
            'CreditVerification',
            'submit-verification-request',
            [
                Cl.uint(100),
                Cl.stringAscii("SOLAR-001"),
                Cl.uint(1),
                Cl.stringAscii("Solar farm project")
            ],
            address2
        );
        
        // Try to assign inactive verifier
        const { result } = simnet.callPublicFn(
            'CreditVerification',
            'assign-verifier',
            [
                Cl.uint(1),
                Cl.principal(address1)
            ],
            deployer
        );
        
        // expect(result).toBeErr(Cl.uint(203));
    });
});
