;; Decentralized Governance Smart Contract

;; Define constants
(define-constant GOVERNANCE_ADMIN tx-sender)
(define-constant ERROR_UNAUTHORIZED (err u100))
(define-constant ERROR_DUPLICATE_VOTE (err u101))
(define-constant ERROR_INVALID_MOTION (err u102))
(define-constant ERROR_VOTING_CLOSED (err u103))
(define-constant ERROR_INVALID_PARAMETERS (err u104))
(define-constant ERROR_MOTION_NOT_FOUND (err u105))
(define-constant ERROR_VOTING_PERIOD_EXPIRED (err u106))
(define-constant MAX_VOTING_WINDOW u2592000) ;; 30 days in seconds
(define-constant MIN_VOTING_WINDOW u86400) ;; 1 day in seconds

;; Define data maps
(define-map governance-motions
  { motion-id: uint }
  { 
    title: (string-ascii 50), 
    description: (string-ascii 500), 
    total-votes: uint, 
    is-active: bool,
    motion-creator: principal,
    creation-timestamp: uint,
    voting-window: uint
  }
)

(define-map voter-participation
  { voter: principal, motion-id: uint }
  { 
    has-participated: bool,
    participation-timestamp: uint
  }
)

;; Define data variables
(define-data-var total-motions uint u0)
(define-data-var standard-voting-window uint u604800) ;; 7 days in seconds

;; Private functions
;; Validate motion input parameters
(define-private (validate-motion-parameters (title (string-ascii 50)) (description (string-ascii 500)))
  (and 
    (> (len title) u0) 
    (<= (len title) u50)
    (> (len description) u0)
    (<= (len description) u500)
  )
)

;; Validate motion identifier
(define-private (validate-motion-id (motion-id uint))
  (and 
    (> motion-id u0)
    (<= motion-id (var-get total-motions))
  )
)

;; Check if a motion is currently active
(define-private (is-motion-active (motion-id uint))
  (match (map-get? governance-motions { motion-id: motion-id })
    motion 
      (and 
        (get is-active motion)
        (< block-height (+ (get creation-timestamp motion) (get voting-window motion)))
      )
    false
  )
)

;; Validate voting window duration
(define-private (validate-voting-window (duration uint))
  (and (>= duration MIN_VOTING_WINDOW) (<= duration MAX_VOTING_WINDOW))
)

;; Public functions
;; Propose a new governance motion
(define-public (propose-motion 
  (title (string-ascii 50)) 
  (description (string-ascii 500))
  (custom-window (optional uint))
)
  (let (
    (new-motion-id (+ (var-get total-motions) u1))
    (voting-window (default-to (var-get standard-voting-window) custom-window))
  )
    ;; Validate sender is governance admin
    (asserts! (is-eq tx-sender GOVERNANCE_ADMIN) ERROR_UNAUTHORIZED)
    
    ;; Validate motion parameters
    (asserts! (validate-motion-parameters title description) ERROR_INVALID_PARAMETERS)
    
    ;; Validate voting window
    (asserts! (validate-voting-window voting-window) ERROR_INVALID_PARAMETERS)
    
    ;; Create motion with extended metadata
    (map-set governance-motions
      { motion-id: new-motion-id }
      { 
        title: title, 
        description: description, 
        total-votes: u0, 
        is-active: true,
        motion-creator: tx-sender,
        creation-timestamp: block-height,
        voting-window: voting-window
      }
    )
    
    ;; Update total motions count
    (var-set total-motions new-motion-id)
    
    (ok new-motion-id)
  )
)

;; Cast a vote on a motion
(define-public (cast-vote (motion-id uint))
  (let (
    (motion (unwrap! (map-get? governance-motions { motion-id: motion-id }) ERROR_INVALID_MOTION))
    (already-voted (default-to false (get has-participated (map-get? voter-participation { voter: tx-sender, motion-id: motion-id }))))
  )
    ;; Validate motion ID
    (asserts! (validate-motion-id motion-id) ERROR_INVALID_MOTION)
    
    ;; Validate motion is active and within voting period
    (asserts! (is-motion-active motion-id) ERROR_VOTING_CLOSED)
    
    ;; Prevent multiple votes
    (asserts! (not already-voted) ERROR_DUPLICATE_VOTE)
    
    ;; Record vote
    (map-set voter-participation 
      { voter: tx-sender, motion-id: motion-id } 
      { 
        has-participated: true,
        participation-timestamp: block-height 
      }
    )
    
    ;; Update motion vote count
    (map-set governance-motions
      { motion-id: motion-id }
      (merge motion { total-votes: (+ (get total-votes motion) u1) })
    )
    
    (ok true)
  )
)

