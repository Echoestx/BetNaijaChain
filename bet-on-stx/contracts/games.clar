;; Crypto Betting Protocol - Version 1
;; Basic implementation with core betting functionality

;; Constants
(define-constant ERR-NOT-PROTOCOL-ADMIN (err u1))
(define-constant ERR-PROTOCOL-OFFLINE (err u2))
(define-constant ERR-INVALID-BET (err u3))
(define-constant ERR-BET-ALREADY-SETTLED (err u4))
(define-constant ERR-INCORRECT-PRICE-PROOF (err u5))

;; Data Variables
(define-data-var protocol-admin principal tx-sender)
(define-data-var protocol-active bool false)
(define-data-var entry-fee uint u1000000) ;; 1 STX

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
        total-wins: uint
    }
)

;; Authorization
(define-private (is-admin)
    (is-eq tx-sender (var-get protocol-admin)))

;; Protocol Management Functions
(define-public (activate-protocol)
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        (var-set protocol-active true)
        (ok true)))

(define-public (create-bet
    (bet-id uint)
    (asset-pair (string-utf8 256))
    (target-price-hash (buff 32))
    (settlement-time uint)
    (reward uint))
    (begin
        (asserts! (is-admin) ERR-NOT-PROTOCOL-ADMIN)
        (map-set crypto-bets bet-id
            {
                asset-pair: asset-pair,
                target-price-hash: target-price-hash,
                settlement-time: settlement-time,
                reward: reward,
                settled: false
            })
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
        )
        ;; Check bet availability
        (asserts! (var-get protocol-active) ERR-PROTOCOL-OFFLINE)
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
                        total-wins: (+ (get total-wins bettor) u1)
                    }))
                
                ;; Distribute reward
                (try! (stx-transfer? (get reward bet) (var-get protocol-admin) tx-sender))
                
                (ok true))
            ERR-INCORRECT-PRICE-PROOF)))

;; Read-only functions
(define-read-only (get-bet-details (bet-id uint))
    (map-get? crypto-bets bet-id))

(define-read-only (get-bettor-profile (bettor principal))
    (map-get? bettor-profiles bettor))

(define-read-only (get-protocol-stats)
    {
        active: (var-get protocol-active),
        entry-fee: (var-get entry-fee)
    })