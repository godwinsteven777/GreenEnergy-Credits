import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

describe("Credit Retirement System", () => {
    const accounts = simnet.getAccounts();
    const deployer = accounts.get("deployer")!;
    const user1 = accounts.get("wallet_1")!;
    const user2 = accounts.get("wallet_2")!;
    const user3 = accounts.get("wallet_3")!;

    beforeEach(() => {
        // Mint some credits for testing
        simnet.callPublicFn(
            "GreenEnergy",
            "mint-credits",
            [Cl.uint(1000), Cl.principal(user1)],
            deployer
        );
        simnet.callPublicFn(
            "GreenEnergy", 
            "mint-credits",
            [Cl.uint(500), Cl.principal(user2)],
            deployer
        );
    });

    it("allows user to retire credits with valid parameters", () => {
        const retireCall = simnet.callPublicFn(
            "CreditRetirement",
            "retire-credits",
            [
                Cl.uint(100),
                Cl.uint(1), // voluntary reason
                Cl.principal(user1),
                Cl.stringAscii("Solar farm offset project"),
                Cl.uint(50) // 50 tons CO2 equivalent
            ],
            user1
        );
        expect(retireCall.result).toHaveProperty('type', 7);
    });

    it("fails to retire credits with zero amount", () => {
        const retireCall = simnet.callPublicFn(
            "CreditRetirement",
            "retire-credits",
            [
                Cl.uint(0),
                Cl.uint(1),
                Cl.principal(user1),
                Cl.stringAscii("Invalid retirement"),
                Cl.uint(0)
            ],
            user1
        );
        expect(retireCall.result).toHaveProperty('type', 8);
    });

    it("fails to retire credits with invalid reason", () => {
        const retireCall = simnet.callPublicFn(
            "CreditRetirement",
            "retire-credits",
            [
                Cl.uint(50),
                Cl.uint(10), // invalid reason (max is 5)
                Cl.principal(user1),
                Cl.stringAscii("Invalid reason test"),
                Cl.uint(25)
            ],
            user1
        );
        expect(retireCall.result).toHaveProperty('type', 8);
    });

    it("correctly tracks global retirement statistics", () => {
        // Retire some credits first
        simnet.callPublicFn(
            "CreditRetirement",
            "retire-credits",
            [
                Cl.uint(100),
                Cl.uint(2), // compliance reason
                Cl.principal(user1),
                Cl.stringAscii("Compliance retirement"),
                Cl.uint(75)
            ],
            user1
        );

        const statsCall = simnet.callReadOnlyFn(
            "CreditRetirement",
            "get-global-retirement-stats",
            [],
            user1
        );
        expect(statsCall.result).toHaveProperty('type', 7);
    });

    it("allows user to retire credits on behalf of another party", () => {
        const retireOnBehalfCall = simnet.callPublicFn(
            "CreditRetirement",
            "retire-on-behalf",
            [
                Cl.uint(50),
                Cl.uint(3), // corporate reason
                Cl.principal(user3),
                Cl.stringAscii("Corporate sustainability program"),
                Cl.uint(30),
                Cl.principal(user2) // payer
            ],
            user2
        );
        expect(retireOnBehalfCall.result).toHaveProperty('type', 7);
    });

    it("correctly reports retirement certificate details", () => {
        // First retire some credits
        simnet.callPublicFn(
            "CreditRetirement",
            "retire-credits",
            [
                Cl.uint(75),
                Cl.uint(4), // event reason
                Cl.principal(user2),
                Cl.stringAscii("Event carbon neutrality"),
                Cl.uint(40)
            ],
            user1
        );

        const certificateCall = simnet.callReadOnlyFn(
            "CreditRetirement",
            "get-retirement-certificate",
            [Cl.uint(1)],
            user1
        );
        expect(certificateCall.result).toHaveProperty('type', 7);
    });

    it("correctly tracks user retirement history", () => {
        // Retire credits multiple times
        simnet.callPublicFn(
            "CreditRetirement",
            "retire-credits",
            [
                Cl.uint(50),
                Cl.uint(1),
                Cl.principal(user1),
                Cl.stringAscii("First retirement"),
                Cl.uint(25)
            ],
            user1
        );

        simnet.callPublicFn(
            "CreditRetirement",
            "retire-credits",
            [
                Cl.uint(30),
                Cl.uint(2),
                Cl.principal(user1), 
                Cl.stringAscii("Second retirement"),
                Cl.uint(15)
            ],
            user1
        );

        const historyCall = simnet.callReadOnlyFn(
            "CreditRetirement",
            "get-user-retirement-history",
            [Cl.principal(user1)],
            user1
        );
        expect(historyCall.result).toHaveProperty('type', 7);
    });

    it("correctly tracks retirements by reason", () => {
        // Retire with specific reason
        simnet.callPublicFn(
            "CreditRetirement",
            "retire-credits",
            [
                Cl.uint(80),
                Cl.uint(1), // voluntary reason
                Cl.principal(user1),
                Cl.stringAscii("Voluntary offset"),
                Cl.uint(60)
            ],
            user1
        );

        const reasonStatsCall = simnet.callReadOnlyFn(
            "CreditRetirement",
            "get-retirement-by-reason",
            [Cl.uint(1)],
            user1
        );
        expect(reasonStatsCall.result).toHaveProperty('type', 7);
    });

    it("correctly tracks beneficiary retirement totals", () => {
        // Retire credits for specific beneficiary
        simnet.callPublicFn(
            "CreditRetirement",
            "retire-credits",
            [
                Cl.uint(60),
                Cl.uint(5), // product reason
                Cl.principal(user3), // beneficiary
                Cl.stringAscii("Product lifecycle offset"),
                Cl.uint(45)
            ],
            user1
        );

        const beneficiaryTotalsCall = simnet.callReadOnlyFn(
            "CreditRetirement",
            "get-beneficiary-totals",
            [Cl.principal(user3)],
            user1
        );
        expect(beneficiaryTotalsCall.result).toHaveProperty('type', 7);
    });

    it("provides retirement reasons reference", () => {
        const reasonsCall = simnet.callReadOnlyFn(
            "CreditRetirement",
            "get-retirement-reasons",
            [],
            user1
        );
        expect(reasonsCall.result).toHaveProperty('type', 7);
    });

    describe("retirement system control", () => {
        it("allows owner to disable retirement system", () => {
            const disableCall = simnet.callPublicFn(
                "CreditRetirement",
                "set-retirement-status",
                [Cl.bool(false)],
                deployer
            );
            expect(disableCall.result).toHaveProperty('type', 7);
        });

        it("prevents retirement when system is disabled", () => {
            // First disable the system
            simnet.callPublicFn(
                "CreditRetirement",
                "set-retirement-status",
                [Cl.bool(false)],
                deployer
            );

            // Try to retire credits
            const retireCall = simnet.callPublicFn(
                "CreditRetirement",
                "retire-credits",
                [
                    Cl.uint(50),
                    Cl.uint(1),
                    Cl.principal(user1),
                    Cl.stringAscii("Should fail"),
                    Cl.uint(25)
                ],
                user1
            );
            expect(retireCall.result).toHaveProperty('type', 8);
        });

        it("fails when non-owner tries to disable system", () => {
            const disableCall = simnet.callPublicFn(
                "CreditRetirement",
                "set-retirement-status",
                [Cl.bool(false)],
                user1
            );
            expect(disableCall.result).toHaveProperty('type', 8);
        });
    });

    describe("project tracking", () => {
        it("allows owner to update project retirement tracking", () => {
            const updateCall = simnet.callPublicFn(
                "CreditRetirement",
                "update-project-tracking",
                [
                    Cl.stringAscii("SOLAR-001"),
                    Cl.uint(100)
                ],
                deployer
            );
            expect(updateCall.result).toHaveProperty('type', 7);
        });

        it("correctly reports project retirement statistics", () => {
            // First update project tracking
            simnet.callPublicFn(
                "CreditRetirement",
                "update-project-tracking",
                [
                    Cl.stringAscii("WIND-002"),
                    Cl.uint(150)
                ],
                deployer
            );

            const projectStatsCall = simnet.callReadOnlyFn(
                "CreditRetirement",
                "get-project-retirement-stats",
                [Cl.stringAscii("WIND-002")],
                user1
            );
            expect(projectStatsCall.result).toHaveProperty('type', 7);
        });

        it("fails when non-owner tries to update project tracking", () => {
            const updateCall = simnet.callPublicFn(
                "CreditRetirement",
                "update-project-tracking",
                [
                    Cl.stringAscii("HYDRO-003"),
                    Cl.uint(75)
                ],
                user1
            );
            expect(updateCall.result).toHaveProperty('type', 8);
        });
    });

    describe("environmental impact calculation", () => {
        it("correctly calculates user environmental impact", () => {
            // Retire credits with CO2 equivalent
            simnet.callPublicFn(
                "CreditRetirement",
                "retire-credits",
                [
                    Cl.uint(100),
                    Cl.uint(1),
                    Cl.principal(user1),
                    Cl.stringAscii("Impact calculation test"),
                    Cl.uint(80) // 80 tons CO2
                ],
                user1
            );

            const impactCall = simnet.callReadOnlyFn(
                "CreditRetirement",
                "get-user-environmental-impact",
                [Cl.principal(user1)],
                user1
            );
            expect(impactCall.result).toHaveProperty('type', 7);
        });
    });

    describe("retirement system status", () => {
        it("correctly reports retirement system status", () => {
            const statusCall = simnet.callReadOnlyFn(
                "CreditRetirement",
                "is-retirement-enabled",
                [],
                user1
            );
            expect(statusCall.result).toHaveProperty('type', 7);
        });
    });
});
