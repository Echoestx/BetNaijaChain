;; Crypto Betting Protocol - Version 2
;; Enhanced implementation with session tracking and bettor history

;; Constants
(define-constant ERR-NOT-PROTOCOL-ADMIN (err u1))
(define-constant ERR-PROTOCOL-OFFLINE (err u2))
(define-constant ERR-INVALID-BET (err u3))
(define-constant ERR-BET-ALREADY-SETTLED (err u4))
(define-constant ERR-INCORRECT-PRICE-PROOF (err u5))
(define-constant ERR-SETTLEMENT-PERIOD-ACTIVE (err u6))
(define-constant ERR-INSUFFICIENT-FUNDS (err u7))
(define-constant ERR-INVALID-INPUT (err u8))

;; Data Variables
(define-data-var protocol-admin principal tx-sender)
(define-data-var protocol-active bool false)
(define-data-var current-session uint u0)
(define-data-var entry-fee uint u1000000) ;; 1 STX
(define-data-var total-prize-pool uint u0)
(define-data-var current-block-height uint u0) ;; Block height tracking for settlement periods

;; Bet Structure
(define-map crypto-bets
    uint
    {
        asset-pair: (string-utf8 256),
        target-price-hash: (buff 32),      
        settlement-time: uint,             
        reward: uint,
        settled: bool
    }
)

;; Bettor Performance Tracking
(define-map bettor-profiles
    principal
    {
        active-bet: uint,
        winning-bets: (list 20 uint),
        last-bet: uint,
        total-wins: uint
    }
)

;; Betting History
(define-map bet-participations
    {bet-id: uint, bettor: principal}
    {
        attempts: uint,
        settled-at: (optional uint)
    }
)

;; Authorization
(define-private (is-admin)
    (is-eq tx-sender (var-get protocol-admin)))

;; Block Height Management
(define-public (update-block-height (new-height uint))
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        ;; Validate block is not less than current
        (asserts! (>= new-height (var-get current-block-height)) ERR-INVALID-INPUT)
        (var-set current-block-height new-height)
        (ok true)))

;; Protocol Management Functions
(define-public (activate-protocol)
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        (var-set protocol-active true)
        (var-set current-session u0)
        (var-set total-prize-pool u0)
        (ok true)))

(define-public (create-bet
    (bet-id uint)
    (asset-pair (string-utf8 256))
    (target-price-hash (buff 32))
    (settlement-time uint)
    (reward uint))
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        
        ;; Validate settlement time is in the future
        (asserts! (>= settlement-time (var-get current-block-height)) ERR-INVALID-INPUT)
        
        ;; Validate target price hash is not empty
        (asserts! (> (len target-price-hash) u0) ERR-INVALID-INPUT)
        
        ;; Validate asset pair is not empty
        (asserts! (> (len asset-pair) u0) ERR-INVALID-INPUT)
        
        ;; Validate reward is a positive amount
        (asserts! (> reward u0) ERR-INVALID-INPUT)
        
        ;; Set the bet data
        (map-set crypto-bets bet-id
            {
                asset-pair: asset-pair,
                target-price-hash: target-price-hash,
                settlement-time: settlement-time,
                reward: reward,
                settled: false
            })
            
        ;; Calculate new prize pool safely
        (let ((new-pool (+ (var-get total-prize-pool) reward)))
            ;; Make sure the addition doesn't overflow
            (asserts! (>= new-pool (var-get total-prize-pool)) ERR-INVALID-INPUT)
            ;; Update the total prize pool
            (var-set total-prize-pool new-pool))
        (ok true)))

;; Bettor Registration
(define-public (register-as-bettor)
    (begin
        (asserts! (var-get protocol-active) ERR-PROTOCOL-OFFLINE)
        ;; Require entry fee
        (try! (stx-transfer? (var-get entry-fee) tx-sender (var-get protocol-admin)))
        
        (map-set bettor-profiles tx-sender
            {
                active-bet: u0,
                winning-bets: (list),
                last-bet: u0,
                total-wins: u0
            })
        (ok true)))

;; Bet Settlement Functions
(define-public (submit-price
    (bet-id uint)
    (price-proof (buff 32)))
    (let (
        (bet (unwrap! (map-get? crypto-bets bet-id) ERR-INVALID-BET))
        (bettor (unwrap! (map-get? bettor-profiles tx-sender) ERR-INVALID-BET))
        (current-block (var-get current-block-height))
        )
        ;; Check bet availability
        (asserts! (var-get protocol-active) ERR-PROTOCOL-OFFLINE)
        (asserts! (>= current-block (get settlement-time bet)) ERR-SETTLEMENT-PERIOD-ACTIVE)
        (asserts! (not (get settled bet)) ERR-BET-ALREADY-SETTLED)
        
        ;; Verify price proof - directly compare the hashes
        (if (is-eq price-proof (get target-price-hash bet))
            (begin
                ;; Update bet status
                (map-set crypto-bets bet-id
                    (merge bet {settled: true}))
                
                ;; Update bettor record
                (map-set bettor-profiles tx-sender
                    (merge bettor {
                        active-bet: (+ bet-id u1),
                        winning-bets: (unwrap! (as-max-len? 
                            (append (get winning-bets bettor) bet-id) u20)
                            ERR-INVALID-BET),
                        total-wins: (+ (get total-wins bettor) u1)
                    }))
                
                ;; Record participation
                (map-set bet-participations
                    {bet-id: bet-id, bettor: tx-sender}
                    {
                        attempts: u1,
                        settled-at: (some current-block)
                    })
                
                ;; Distribute reward
                (try! (stx-transfer? (get reward bet) (var-get protocol-admin) tx-sender))
                
                (ok true))
            ERR-INCORRECT-PRICE-PROOF)))

;; Read-only functions
(define-read-only (get-bet-details (bet-id uint))
    (match (map-get? crypto-bets bet-id)
        bet (if (>= (var-get current-block-height) (get settlement-time bet))
            (ok (get asset-pair bet))
            ERR-SETTLEMENT-PERIOD-ACTIVE)
        ERR-INVALID-BET))

(define-read-only (get-bettor-profile (bettor principal))
    (map-get? bettor-profiles bettor))

(define-read-only (get-current-height)
    (var-get current-block-height))

(define-read-only (get-protocol-stats)
    {
        active: (var-get protocol-active),
        current-session: (var-get current-session),
        total-prize-pool: (var-get total-prize-pool),
        entry-fee: (var-get entry-fee),
        current-block-height: (var-get current-block-height)
    })