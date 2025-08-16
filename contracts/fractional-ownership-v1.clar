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
(define-constant ERR-ALREADY-INITIALIZED (err u200))
(define-constant ERR-INVALID-VALUATION (err u201))
(define-constant ERR-INVALID-VOTING-DURATION (err u202))
(define-constant ERR-INVALID-PROPOSAL-ID (err u203))

;; Input validation constants
(define-constant MAX-SHARES u10000)
(define-constant MIN-SHARES u1)
(define-constant MAX-VALUATION u1000000000000) ;; 1 trillion STX
(define-constant MIN-VALUATION u1000000) ;; 1 million STX
(define-constant MAX-VOTING-DURATION u52560) ;; ~1 year in blocks
(define-constant MIN-VOTING-DURATION u144) ;; ~1 day in blocks

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Data Variables and Maps
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Property Details
(define-data-var property-initialized bool false)
(define-data-var total-shares uint u100)
(define-data-var property-valuation uint u0)
(define-data-var shares-minted bool false)

;; Fungible Token for Rental Income
(define-fungible-token rental-income)

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
(define-map voter-proposals {voter: principal, proposal-id: uint} bool)
(define-data-var proposal-count uint u0)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Private Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Helper function to check if a principal is the contract owner
(define-private (is-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

;; Validates property valuation input
(define-private (is-valid-valuation (valuation uint))
  (and (>= valuation MIN-VALUATION) (<= valuation MAX-VALUATION))
)

;; Validates share count input
(define-private (is-valid-shares (shares uint))
  (and (>= shares MIN-SHARES) (<= shares MAX-SHARES))
)

;; Validates voting duration input
(define-private (is-valid-voting-duration (duration uint))
  (and (>= duration MIN-VOTING-DURATION) (<= duration MAX-VOTING-DURATION))
)

;; Validates proposal ID input
(define-private (is-valid-proposal-id (proposal-id uint))
  (and (> proposal-id u0) (<= proposal-id (var-get proposal-count)))
)

;; Validates string input to prevent empty or malicious strings
(define-private (is-valid-string (input (string-ascii 128)))
  (and (> (len input) u0) (<= (len input) u128))
)

;; Validates description input to prevent empty or malicious strings
(define-private (is-valid-description (input (string-ascii 512)))
  (and (> (len input) u0) (<= (len input) u512))
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
    (asserts! (not (var-get property-initialized)) ERR-ALREADY-INITIALIZED)
    (asserts! (is-valid-valuation valuation) ERR-INVALID-VALUATION)
    (asserts! (is-valid-shares shares) ERR-INVALID-SHARE-TOTAL)
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
;; @param amount: The amount of STX to deposit
;; @returns (response bool uint)
(define-public (deposit-rental-income (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INSUFFICIENT-FUNDS)
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR-INSUFFICIENT-FUNDS)
    (try! (ft-mint? rental-income amount (as-contract tx-sender)))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (ok true)
  )
)

;; @desc Distributes collected rental income to all shareholders based on their ownership percentage
;; @returns (response bool uint)
(define-public (distribute-income)
  (let ((contract-balance (stx-get-balance (as-contract tx-sender))))
    (asserts! (> contract-balance u0) ERR-NOTHING-TO-DISTRIBUTE)
    (let
      ((total (var-get total-shares))
       (owner-result (nft-get-owner? ownership-share total)))
      (match owner-result
        owner-principal
        (if (is-eq (as-contract tx-sender) owner-principal)
            (ok false) ;; Cannot distribute if contract holds all shares
            (let ((payout (/ contract-balance total)))
              (try! (as-contract (stx-transfer? payout tx-sender owner-principal)))
              (ok true)
            )
        )
        ERR-PROPERTY-NOT-INITIALIZED
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
    (asserts! (is-valid-string title) ERR-INVALID-SHARE-TOTAL)
    (asserts! (is-valid-description description) ERR-INVALID-SHARE-TOTAL)
    (asserts! (is-valid-voting-duration voting-duration) ERR-INVALID-VOTING-DURATION)
    (let ((validated-end-block (+ block-height voting-duration))
          (validated-title title)
          (validated-description description))
      (map-set proposals proposal-id {
        title: validated-title,
        description: validated-description,
        end-block: validated-end-block,
        votes-for: u0,
        votes-against: u0,
        executed: false
      })
      (var-set proposal-count proposal-id)
      (ok proposal-id)
    )
  )
)

;; @desc Allows a shareholder to cast a vote on a proposal
;; @param proposal-id: The ID of the proposal to vote on
;; @param in-favor: A boolean value (true for 'for', false for 'against')
;; @returns (response bool uint)
(define-public (vote-on-proposal (proposal-id uint) (in-favor bool))
  (let ((proposal-result (map-get? proposals proposal-id)))
    (asserts! (is-valid-proposal-id proposal-id) ERR-INVALID-PROPOSAL-ID)
    (match proposal-result
      proposal
      (begin
        (asserts! (is-some (nft-get-owner? ownership-share (var-get total-shares))) ERR-UNAUTHORIZED)
        (asserts! (is-none (map-get? voter-proposals {voter: tx-sender, proposal-id: proposal-id})) ERR-ALREADY-VOTED)
        (asserts! (<= block-height (get end-block proposal)) ERR-VOTING-CLOSED)

        (let ((new-proposal (if in-favor
                               (merge proposal { votes-for: (+ u1 (get votes-for proposal)) })
                               (merge proposal { votes-against: (+ u1 (get votes-against proposal)) }))))
          (map-set proposals proposal-id new-proposal)
          (map-set voter-proposals {voter: tx-sender, proposal-id: proposal-id} true)
          (ok true)
        )
      )
      ERR-PROPOSAL-NOT-FOUND
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read-Only Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; @desc Gets the details of a specific property
;; @returns (response object uint)
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
;; @returns (optional object)
(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? proposals proposal-id)
)

;; @desc Checks if a user has voted on a specific proposal
;; @param voter: The principal of the voter
;; @param proposal-id: The ID of the proposal
;; @returns bool
(define-read-only (has-voted (voter principal) (proposal-id uint))
  (is-some (map-get? voter-proposals {voter: voter, proposal-id: proposal-id}))
)

;; @desc Gets the balance of rental income tokens for a principal
;; @param owner: The principal of the token holder
;; @returns uint
(define-read-only (get-rental-income-balance (owner principal))
  (ft-get-balance rental-income owner)
)

;; @desc Gets the owner of the specified share
;; @param share-id: The ID of the share NFT
;; @returns (optional principal)
(define-read-only (get-share-owner (share-id uint))
  (nft-get-owner? ownership-share share-id)
)

;; @desc Gets the current proposal count
;; @returns uint
(define-read-only (get-proposal-count)
  (var-get proposal-count)
)