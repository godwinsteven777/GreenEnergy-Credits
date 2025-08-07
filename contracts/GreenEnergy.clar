;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-listing-not-found (err u103))
(define-constant err-insufficient-payment (err u104))
(define-constant err-cannot-buy-own-listing (err u105))
(define-constant err-no-stake-found (err u106))
(define-constant err-stake-locked (err u107))
(define-constant min-stake-amount u10)
(define-constant reward-rate u5)
(define-constant stake-lock-period u144)

;; data vars
(define-data-var total-credits uint u0)
(define-data-var listing-counter uint u0)
(define-data-var total-staked uint u0)
(define-data-var rewards-pool uint u0)

;; data maps
(define-map credit-balances principal uint)
(define-map credit-verification principal bool)
(define-map offset-records 
    principal 
    {total-offset: uint, last-update: uint}
)
(define-map marketplace-listings
    uint
    {seller: principal, amount: uint, price-per-credit: uint, active: bool}
)
(define-map user-listings principal (list 20 uint))
(define-map staking-positions
    principal
    {staked-amount: uint, stake-time: uint, last-reward-claim: uint}
)

;; public functions
(define-public (mint-credits (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        (map-set credit-balances recipient 
            (+ (default-to u0 (map-get? credit-balances recipient)) amount))
        (var-set total-credits (+ (var-get total-credits) amount))
        (ok true)))

(define-public (transfer-credits (amount uint) (sender principal) (recipient principal))
    (let ((sender-balance (default-to u0 (map-get? credit-balances sender))))
        (asserts! (>= sender-balance amount) err-insufficient-balance)
        (asserts! (is-eq tx-sender sender) err-owner-only)
        (map-set credit-balances sender (- sender-balance amount))
        (map-set credit-balances recipient 
            (+ (default-to u0 (map-get? credit-balances recipient)) amount))
        (ok true)))

(define-public (record-offset (amount uint))
    (let ((current-time stacks-block-height))
        (map-set offset-records tx-sender 
            {total-offset: (+ (get-offset-total tx-sender) amount),
             last-update: current-time})
        (ok true)))

(define-public (create-listing (amount uint) (price-per-credit uint))
    (let (
        (seller-balance (get-credit-balance tx-sender))
        (listing-id (+ (var-get listing-counter) u1))
        (current-listings (default-to (list) (map-get? user-listings tx-sender)))
    )
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (> price-per-credit u0) err-invalid-amount)
        (asserts! (>= seller-balance amount) err-insufficient-balance)
        (map-set credit-balances tx-sender (- seller-balance amount))
        (map-set marketplace-listings listing-id
            {seller: tx-sender, amount: amount, price-per-credit: price-per-credit, active: true})
        (map-set user-listings tx-sender (unwrap-panic (as-max-len? (append current-listings listing-id) u20)))
        (var-set listing-counter listing-id)
        (ok listing-id)))

(define-public (buy-credits (listing-id uint))
    (let (
        (listing (unwrap! (map-get? marketplace-listings listing-id) err-listing-not-found))
        (seller (get seller listing))
        (amount (get amount listing))
        (price-per-credit (get price-per-credit listing))
        (total-price (* amount price-per-credit))
        (buyer-balance (stx-get-balance tx-sender))
    )
        (asserts! (get active listing) err-listing-not-found)
        (asserts! (not (is-eq tx-sender seller)) err-cannot-buy-own-listing)
        (asserts! (>= buyer-balance total-price) err-insufficient-payment)
        (try! (stx-transfer? total-price tx-sender seller))
        (map-set credit-balances tx-sender 
            (+ (get-credit-balance tx-sender) amount))
        (map-set marketplace-listings listing-id
            (merge listing {active: false}))
        (ok true)))

(define-public (cancel-listing (listing-id uint))
    (let (
        (listing (unwrap! (map-get? marketplace-listings listing-id) err-listing-not-found))
        (seller (get seller listing))
        (amount (get amount listing))
    )
        (asserts! (is-eq tx-sender seller) err-owner-only)
        (asserts! (get active listing) err-listing-not-found)
        (map-set credit-balances seller 
            (+ (get-credit-balance seller) amount))
        (map-set marketplace-listings listing-id
            (merge listing {active: false}))
        (ok true)))

(define-public (stake-credits (amount uint))
    (let (
        (current-balance (get-credit-balance tx-sender))
        (current-time stacks-block-height)
        (existing-stake (map-get? staking-positions tx-sender))
    )
        (asserts! (>= amount min-stake-amount) err-invalid-amount)
        (asserts! (>= current-balance amount) err-insufficient-balance)
        (map-set credit-balances tx-sender (- current-balance amount))
        (match existing-stake
            existing-pos (map-set staking-positions tx-sender
                {staked-amount: (+ (get staked-amount existing-pos) amount),
                 stake-time: current-time,
                 last-reward-claim: current-time})
            (map-set staking-positions tx-sender
                {staked-amount: amount,
                 stake-time: current-time,
                 last-reward-claim: current-time}))
        (var-set total-staked (+ (var-get total-staked) amount))
        (ok true)))

(define-public (unstake-credits (amount uint))
    (let (
        (stake-info (unwrap! (map-get? staking-positions tx-sender) err-no-stake-found))
        (staked-amount (get staked-amount stake-info))
        (stake-time (get stake-time stake-info))
        (current-time stacks-block-height)
        (new-staked (- staked-amount amount))
    )
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (>= staked-amount amount) err-insufficient-balance)
        (asserts! (>= current-time (+ stake-time stake-lock-period)) err-stake-locked)
        (map-set credit-balances tx-sender 
            (+ (get-credit-balance tx-sender) amount))
        (if (is-eq new-staked u0)
            (map-delete staking-positions tx-sender)
            (map-set staking-positions tx-sender
                (merge stake-info {staked-amount: new-staked})))
        (var-set total-staked (- (var-get total-staked) amount))
        (ok true)))

(define-public (claim-rewards)
    (let (
        (stake-info (unwrap! (map-get? staking-positions tx-sender) err-no-stake-found))
        (staked-amount (get staked-amount stake-info))
        (last-claim (get last-reward-claim stake-info))
        (current-time stacks-block-height)
        (time-diff (- current-time last-claim))
        (rewards (* (/ (* staked-amount reward-rate) u100) time-diff))
    )
        (asserts! (> rewards u0) err-invalid-amount)
        (map-set credit-balances tx-sender 
            (+ (get-credit-balance tx-sender) rewards))
        (map-set staking-positions tx-sender
            (merge stake-info {last-reward-claim: current-time}))
        (var-set total-credits (+ (var-get total-credits) rewards))
        (ok rewards)))

(define-public (fund-rewards-pool (amount uint))
    (let ((owner-balance (get-credit-balance tx-sender)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (>= owner-balance amount) err-insufficient-balance)
        (map-set credit-balances tx-sender (- owner-balance amount))
        (var-set rewards-pool (+ (var-get rewards-pool) amount))
        (ok true)))

;; read only functions
(define-read-only (get-credit-balance (account principal))
    (default-to u0 (map-get? credit-balances account)))

(define-read-only (get-offset-total (account principal))
    (default-to u0 (get total-offset (map-get? offset-records account))))

(define-read-only (get-total-credits)
    (var-get total-credits))

(define-read-only (get-listing (listing-id uint))
    (map-get? marketplace-listings listing-id))

(define-read-only (get-user-listings (user principal))
    (default-to (list) (map-get? user-listings user)))

(define-read-only (get-listing-counter)
    (var-get listing-counter))

(define-read-only (get-staking-position (account principal))
    (map-get? staking-positions account))

(define-read-only (get-pending-rewards (account principal))
    (match (map-get? staking-positions account)
        stake-info (let (
            (staked-amount (get staked-amount stake-info))
            (last-claim (get last-reward-claim stake-info))
            (current-time stacks-block-height)
            (time-diff (- current-time last-claim))
        )
            (some (* (/ (* staked-amount reward-rate) u100) time-diff)))
        none))

(define-read-only (get-total-staked)
    (var-get total-staked))

(define-read-only (get-rewards-pool)
    (var-get rewards-pool))

(define-read-only (get-staking-info)
    {total-staked: (var-get total-staked),
     rewards-pool: (var-get rewards-pool),
     min-stake: min-stake-amount,
     reward-rate: reward-rate,
     lock-period: stake-lock-period})
