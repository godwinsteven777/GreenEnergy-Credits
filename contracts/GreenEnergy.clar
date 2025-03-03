
;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-insufficient-balance (err u102))

;; data vars
(define-data-var total-credits uint u0)

;; data maps
(define-map credit-balances principal uint)
(define-map credit-verification principal bool)
(define-map offset-records 
    principal 
    {total-offset: uint, last-update: uint}
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

;; read only functions
(define-read-only (get-credit-balance (account principal))
    (default-to u0 (map-get? credit-balances account)))

(define-read-only (get-offset-total (account principal))
    (default-to u0 (get total-offset (map-get? offset-records account))))

(define-read-only (get-total-credits)
    (var-get total-credits))



;; Add to data maps
(define-map credit-expiry principal uint)

;; Add public function
(define-public (set-credit-expiry (account principal) (expiry-height uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set credit-expiry account expiry-height)
        (ok true)))


;; Add to data maps
(define-map credit-batches 
    uint 
    {source: (string-ascii 50), amount: uint, timestamp: uint})
(define-data-var batch-counter uint u0)

;; Add public function
(define-public (create-credit-batch (source (string-ascii 50)) (amount uint))
    (let ((batch-id (+ (var-get batch-counter) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set credit-batches batch-id 
            {source: source, 
             amount: amount, 
             timestamp: stacks-block-height})
        (var-set batch-counter batch-id)
        (ok batch-id)))


;; Add to data maps
(define-map credit-listings
    uint
    {seller: principal, amount: uint, price: uint})
(define-data-var listing-counter uint u0)

;; Add public function
(define-public (list-credits (amount uint) (price uint))
    (let ((listing-id (+ (var-get listing-counter) u1)))
        (asserts! (>= (get-credit-balance tx-sender) amount) err-insufficient-balance)
        (map-set credit-listings listing-id 
            {seller: tx-sender, amount: amount, price: price})
        (var-set listing-counter listing-id)
        (ok listing-id)))


;; Add to data maps
(define-map verifier-list principal bool)

;; Add public functions
(define-public (add-verifier (verifier principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set verifier-list verifier true)
        (ok true)))

(define-public (verify-credits (account principal))
    (begin
        (asserts! (default-to false (map-get? verifier-list tx-sender)) err-owner-only)
        (map-set credit-verification account true)
        (ok true)))


;; Add to data maps
(define-map staked-credits
    principal
    {amount: uint, stake-height: uint})

;; Add public function
(define-public (stake-credits (amount uint))
    (let ((current-balance (get-credit-balance tx-sender)))
        (asserts! (>= current-balance amount) err-insufficient-balance)
        (map-set staked-credits tx-sender 
            {amount: amount, stake-height: stacks-block-height})
        (map-set credit-balances tx-sender (- current-balance amount))
        (ok true)))



;; Add to data maps
(define-map offset-projects
    uint
    {name: (string-ascii 50), 
     owner: principal,
     total-credits: uint})
(define-data-var project-counter uint u0)

;; Add public function
(define-public (register-project (name (string-ascii 50)))
    (let ((project-id (+ (var-get project-counter) u1)))
        (map-set offset-projects project-id
            {name: name,
             owner: tx-sender,
             total-credits: u0})
        (var-set project-counter project-id)
        (ok project-id)))


;; Add public function
(define-public (burn-credits (amount uint))
    (let ((current-balance (get-credit-balance tx-sender)))
        (asserts! (>= current-balance amount) err-insufficient-balance)
        (map-set credit-balances tx-sender (- current-balance amount))
        (var-set total-credits (- (var-get total-credits) amount))
        (ok true)))
;; Add to data maps
(define-map credit-delegates
    principal
    {delegate: principal, amount: uint})

;; Add public function
(define-public (delegate-credits (delegate principal) (amount uint))
    (let ((current-balance (get-credit-balance tx-sender)))
        (asserts! (>= current-balance amount) err-insufficient-balance)
        (map-set credit-delegates tx-sender
            {delegate: delegate, amount: amount})
        (ok true)))
