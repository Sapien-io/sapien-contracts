# Sapien Trust (Proof of Quality)

`SapienTrust` is the identity and reputation layer of the Sapien protocol. It implements the **Proof of Quality (PoQ)** system, which tracks the historical performance of all participants (Originators, Contributors, and Validators).

## 📋 Responsibilities

- **Reputation Tracking**: Managing scores for different roles based on success/failure and quality of work.
- **Skill Validation**: Tracking user expertise in specific domains (e.g., "Image Annotation", "NLP").
- **Role Verification**: Checking if a user meets the minimum stake and reputation requirements for a role.

## 📈 Reputation System (PoQ)

Reputation scores range from **500 to 10000** (where 5000 is the neutral starting point).

### Role-Based Scores
Users have separate reputation scores for each role:
- `ORIGINATOR_ROLE`
- `CONTRIBUTOR_ROLE`
- `VALIDATOR_ROLE`

### Update Logic
Reputation is updated via the `updateReputation` function, which is called by `SapienCore` during finalization:
- **Success**: Increases the score by **+10 bps** (0.1%), with an additional quality bonus for high scores (>5000).
- **Rejection**: Decreases the score by **-50 bps** (0.5%).
- **Slash (Outlier)**: Decreases the score by **-100 bps** (1.0%).

### Lazy Decay
Reputation naturally decays over time if a user is inactive, incentivizing consistent high-quality participation.
- **Mechanism**: The decay is applied "lazily" when a user's reputation is queried or updated.
- **Rate**: Configurable via `reputationDecayPerDay` (expressed in basis points).

## 🧠 Skills

The protocol supports domain-specific skills. When an Originator marks a project as requiring a specific skill (e.g., "Medical Labeling"):
1. Only users with that validated skill can participate.
2. Successful completion of contributions in that project can automatically validate the skill for the contributor and increment their `completionCount`.

## 🛡️ Sybil Resistance

To prevent reputation farming via multiple accounts (Sybil attacks), `SapienTrust` implements several defenses:
1. **Entry Stake**: Users must have a minimum stake in `SapienVault` to be considered for any role.
2. **Skin in the Game**: High-value roles require higher minimum stakes (configurable via `roleMinStake`).
3. **Reputation Floor**: Scores cannot drop below 500, but low reputation restricts access to high-reward projects.

## 🛠️ Key Functions

- `getTrustScore`: Query a user's reputation for a specific role.
- `hasEnoughStakeForRole`: Check if a user meets the stake and reputation requirements to act as a contributor or validator.
- `validateSkill`: Mark a specific skill as verified for a user.
