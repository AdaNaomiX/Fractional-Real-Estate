;; fractional-ownership-v1
;; This contract manages fractional ownership of a real estate asset.
;; It allows for the minting of ownership-share NFTs, a voting mechanism for property decisions,
;; and distribution of rental income to shareholders.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Constants and Contract Owner
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-VOTING-CLOSED (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-INVALID-SHARE-TOTAL (err u104))
(define-constant ERR-PROPERTY-NOT-INITIALIZED (err u105))
(define-constant ERR-SHARES-ALREADY-MINTED (err u106))
(define-constant ERR-INSUFFICIENT-FUNDS (err u107))
(define-constant ERR-NOTHING-TO-DISTRIBUTE (err u108))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Data Variables and Maps
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Property Details
(define-data-var property-initialized bool false)
(define-data-var total-shares uint u100)
(define-data-var property-valuation uint u0)
(define-data-var shares-minted bool false)

;; Fungible Token for Rental Income
(define-fungible-token rental-income u0)

;; Non-Fungible Token for Ownership Shares
(define-non-fungible-token ownership-share uint)

;; Proposal and Voting
(define-map proposals uint {
  title: (string-ascii 128),
  description: (string-ascii 512),
  end-block: uint,
  votes-for: uint,
  votes-against: uint,
  executed: bool
})
(define-map voter-proposals (tuple principal uint) bool)
(define-data-var proposal-count uint u0)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Private Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Helper function to check if a principal is the contract owner
(define-private (is-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Public: Administrative Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; @desc Initializes the property details and total ownership shares
;; @param valuation: The total valuation of the property
;; @param shares: The number of shares to divide the property into (e.g., 100)
;; @returns (response bool uint)
(define-public (initialize-property (valuation uint) (shares uint))
  (begin
    (asserts! (is-owner) ERR-UNAUTHORIZED)
    (asserts! (not (var-get property-initialized)) (err u200)) ;; ERR-ALREADY-INITIALIZED
    (asserts! (> shares u0) ERR-INVALID-SHARE-TOTAL)
    (var-set property-initialized true)
    (var-set property-valuation valuation)
    (var-set total-shares shares)
    (ok true)
  )
)

;; @desc Mints the initial set of ownership shares to the contract owner for distribution
;; @returns (response bool uint)
(define-public (mint-initial-shares)
  (begin
    (asserts! (is-owner) ERR-UNAUTHORIZED)
    (asserts! (var-get property-initialized) ERR-PROPERTY-NOT-INITIALIZED)
    (asserts! (not (var-get shares-minted)) ERR-SHARES-ALREADY-MINTED)

    (try! (nft-mint? ownership-share (var-get total-shares) CONTRACT-OWNER))
    (var-set shares-minted true)
    (ok true)
  )
)

;; @desc Deposits rental income (in STX) into the contract for later distribution
;; @returns (response bool uint)
(define-public (deposit-rental-income)
  (begin
    (asserts! (> (stx-get-balance tx-sender) u0) ERR-INSUFFICIENT-FUNDS)
    (let ((amount (stx-get-balance tx-sender)))
      (try! (ft-mint? rental-income amount (as-contract tx-sender)))
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (ok true)
    )
  )
)

;; @desc Distributes collected rental income to all shareholders based on their ownership percentage
;; @returns (response bool uint)
(define-public (distribute-income)
  (let ((contract-balance (stx-get-balance (as-contract tx-sender))))
    (asserts! (> contract-balance u0) ERR-NOTHING-TO-DISTRIBUTE)
    (let
      ((total (var-get total-shares))
       (owner (unwrap! (nft-get-owner? ownership-share total) (panic ERR-PROPERTY-NOT-INITIALIZED))))
      (if (is-eq (as-contract tx-sender) owner)
          (ok false) ;; Cannot distribute if contract holds all shares
          (let ((payout (/ (* contract-balance u10000) total)))
            (try! (stx-transfer? (/ (* payout total) u10000) (as-contract tx-sender) owner))
            (ok true)
          )
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Public: Voting Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; @desc Creates a new proposal for shareholders to vote on
;; @param title: The title of the proposal
;; @param description: A detailed description
;; @param voting-duration: Number of blocks the vote will be active
;; @returns (response uint uint)
(define-public (create-proposal (title (string-ascii 128)) (description (string-ascii 512)) (voting-duration uint))
  (let ((proposal-id (+ u1 (var-get proposal-count))))
    (asserts! (var-get property-initialized) ERR-PROPERTY-NOT-INITIALIZED)
    (map-set proposals proposal-id {
      title: title,
      description: description,
      end-block: (+ block-height voting-duration),
      votes-for: u0,
      votes-against: u0,
      executed: false
    })
    (var-set proposal-count proposal-id)
    (ok proposal-id)
  )
)

;; @desc Allows a shareholder to cast a vote on a proposal
;; @param proposal-id: The ID of the proposal to vote on
;; @param vote: A boolean value (true for 'for', false for 'against')
;; @returns (response bool uint)
(define-public (vote-on-proposal (proposal-id uint) (in-favor bool))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
    (asserts! (is-owner-of? ownership-share (var-get total-shares) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? voter-proposals (tuple tx-sender proposal-id))) ERR-ALREADY-VOTED)
    (asserts! (<= block-height (get end-block proposal)) ERR-VOTING-CLOSED)

    (let ((new-proposal (if in-favor
                           (merge proposal { votes-for: (+ u1 (get votes-for proposal)) })
                           (merge proposal { votes-against: (+ u1 (get votes-against proposal)) }))))
      (map-set proposals proposal-id new-proposal)
      (map-set voter-proposals (tuple tx-sender proposal-id) true)
      (ok true)
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read-Only Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; @desc Gets the details of a specific property
;; @returns (response object)
(define-read-only (get-property-details)
  (if (var-get property-initialized)
    (ok {
      valuation: (var-get property-valuation),
      total-shares: (var-get total-shares),
      shares-minted: (var-get shares-minted)
    })
    ERR-PROPERTY-NOT-INITIALIZED
  )
)

;; @desc Gets the details of a specific proposal
;; @param proposal-id: The ID of the proposal
;; @returns (response object)
(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? proposals proposal-id)
)

;; @desc Checks if a user has voted on a specific proposal
;; @param voter: The principal of the voter
;; @param proposal-id: The ID of the proposal
;; @returns bool
(define-read-only (has-voted (voter principal) (proposal-id uint))
  (is-some (map-get? voter-proposals (tuple voter proposal-id)))
)

;; @desc Gets the balance of rental income tokens for a principal
;; @param owner: The principal of the token holder
;; @returns uint
(define-read-only (get-rental-income-balance (owner principal))
  (ft-get-balance rental-income owner)
)

;; @desc Gets the owner of the specified share
;; @param share-id: The ID of the share NFT
;; @returns (response principal uint)
(define-read-only (get-share-owner (share-id uint))
  (ok (unwrap! (nft-get-owner? ownership-share share-id) (panic u0)))
)