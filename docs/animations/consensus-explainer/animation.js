/**
 * Sapien Validator Consensus - Explainer Animation
 * Built with GSAP (GreenSock Animation Platform)
 * 
 * This animation explains the Proof of Quality consensus flow:
 * 1. Project Creation
 * 2. Contribution Submission
 * 3. Commit Phase (hidden scores)
 * 4. Reveal Phase (scores visible)
 * 5. Consensus Calculation
 * 6. Outcome (rewards/slashing)
 */

// ============================================
// CONFIGURATION
// ============================================

const CONFIG = {
    duration: {
        fade: 0.4,
        move: 0.6,
        arrow: 0.8,
        phase: 1.0,
        pause: 0.5
    },
    ease: {
        default: "power2.out",
        bounce: "back.out(1.7)",
        smooth: "power1.inOut"
    }
};

// ============================================
// CAPTIONS FOR EACH STEP
// ============================================

const CAPTIONS = {
    intro: "Welcome to the Sapien Proof of Quality consensus flow",
    projectCreate: "An Originator creates a project with a reward pool and validation requirements",
    projectRegister: "The project is registered with SapienCore and settings are configured",
    contributorClaim: "A Contributor claims a slot to submit work, locking their stake as collateral",
    contributorSubmit: "The Contributor submits their work (stored as a content hash)",
    enqueue: "The contribution is added to the validation queue",
    validatorsClaim: "Validators claim validation slots, committing their stake",
    commitPhase: "COMMIT PHASE: Validators submit hidden score hashes to prevent copying",
    v1Commit: "Validator 1 commits hash(score, stake, salt) — actual score hidden",
    v2Commit: "Validator 2 commits their hidden score hash",
    v3Commit: "Validator 3 commits their hidden score hash",
    revealPhase: "REVEAL PHASE: Validators reveal their actual scores",
    v1Reveal: "Validator 1 reveals: 85% quality score",
    v2Reveal: "Validator 2 reveals: 80% quality score",
    v3Reveal: "Validator 3 reveals: 30% quality score — significantly different!",
    consensusPhase: "CONSENSUS: The Oracle calculates weighted consensus",
    calcWeights: "Weights calculated: √(Stake) — square root stake weighting",
    calcAverage: "Weighted Average = 82% (higher-rep validators have more influence)",
    identifyOutliers: "Validator 3 identified as OUTLIER (30% vs 82% consensus)",
    outcomePhase: "OUTCOME: Contribution accepted, rewards distributed",
    accepted: "Score 82% ≥ 50% threshold → CONTRIBUTION ACCEPTED",
    distributeRewards: "Accurate validators (V1, V2) receive rewards proportional to stake × reputation",
    slashOutlier: "Validator 3 is SLASHED for deviating significantly from consensus",
    contributorReward: "Contributor receives their reward for accepted work",
    summary: "The Proof of Quality protocol ensures honest validation through stake-weighted consensus"
};

// ============================================
// DOM ELEMENTS
// ============================================

const elements = {
    // Controls
    playBtn: document.getElementById('play-btn'),
    restartBtn: document.getElementById('restart-btn'),
    progressFill: document.getElementById('progress-fill'),
    
    // Caption
    captionText: document.getElementById('caption-text'),
    
    // Phase overlay
    phaseOverlay: document.getElementById('phase-overlay'),
    phaseText: document.getElementById('phase-text'),
    
    // Title
    title: document.getElementById('title'),
    
    // Headers
    headers: document.querySelectorAll('.actor-header'),
    
    // Action nodes (organized by actor)
    originator: {
        create: document.getElementById('originator-create')
    },
    contributor: {
        claim: document.getElementById('contributor-claim'),
        submit: document.getElementById('contributor-submit'),
        reward: document.getElementById('contributor-reward')
    },
    v1: {
        claim: document.getElementById('v1-claim'),
        commit: document.getElementById('v1-commit'),
        reveal: document.getElementById('v1-reveal'),
        reward: document.getElementById('v1-reward')
    },
    v2: {
        claim: document.getElementById('v2-claim'),
        commit: document.getElementById('v2-commit'),
        reveal: document.getElementById('v2-reveal'),
        reward: document.getElementById('v2-reward')
    },
    v3: {
        claim: document.getElementById('v3-claim'),
        commit: document.getElementById('v3-commit'),
        reveal: document.getElementById('v3-reveal'),
        slash: document.getElementById('v3-slash')
    },
    core: {
        register: document.getElementById('core-register'),
        enqueue: document.getElementById('core-enqueue'),
        finalize: document.getElementById('core-finalize'),
        distribute: document.getElementById('core-distribute')
    },
    oracle: {
        queue: document.getElementById('oracle-queue'),
        collect: document.getElementById('oracle-collect'),
        reveals: document.getElementById('oracle-reveals'),
        calc: document.getElementById('oracle-calc')
    },
    consensus: {
        weights: document.getElementById('consensus-weights'),
        avg: document.getElementById('consensus-avg'),
        outliers: document.getElementById('consensus-outliers'),
        result: document.getElementById('consensus-result')
    }
};

// ============================================
// HELPER FUNCTIONS
// ============================================

function setCaption(text) {
    gsap.to(elements.captionText, {
        opacity: 0,
        duration: 0.2,
        onComplete: () => {
            elements.captionText.textContent = text;
            gsap.to(elements.captionText, { opacity: 1, duration: 0.2 });
        }
    });
}

function animatePhaseIn(tl, text, className = '') {
    // Add phase animation to timeline - this ensures it runs during playback
    tl.call(() => {
        elements.phaseOverlay.className = 'phase-overlay ' + className;
        elements.phaseText.textContent = text;
    })
    .set(elements.phaseOverlay, { y: -20 })
    .to(elements.phaseOverlay, { 
        opacity: 1, 
        y: 0, 
        duration: CONFIG.duration.fade,
        ease: CONFIG.ease.bounce
    });
}

function animatePhaseOut(tl) {
    // Add phase hide animation to timeline
    tl.to(elements.phaseOverlay, { 
        opacity: 0, 
        y: -20, 
        duration: CONFIG.duration.fade
    })
    .call(() => {
        elements.phaseText.textContent = '';
        elements.phaseOverlay.className = 'phase-overlay';
    });
}

function showNode(node, options = {}) {
    return gsap.to(node, {
        opacity: 1,
        scale: 1,
        duration: options.duration || CONFIG.duration.fade,
        ease: options.ease || CONFIG.ease.bounce
    });
}

function highlightNode(node) {
    node.classList.add('highlight');
    setTimeout(() => node.classList.remove('highlight'), 500);
}

function shakeNode(node) {
    node.classList.add('shake');
    setTimeout(() => node.classList.remove('shake'), 300);
}

function updateProgress(progress) {
    elements.progressFill.style.width = `${progress * 100}%`;
}

// ============================================
// MAIN TIMELINE
// ============================================

let mainTimeline = null;
let isPlaying = false;

function createTimeline() {
    const tl = gsap.timeline({
        paused: true,
        onUpdate: function() {
            updateProgress(this.progress());
        },
        onComplete: function() {
            isPlaying = false;
            elements.playBtn.textContent = '▶ Play';
            elements.playBtn.disabled = false;
        }
    });

    // ============================================
    // PHASE 0: INTRO
    // ============================================
    
    tl.addLabel("intro")
        .call(() => setCaption(CAPTIONS.intro))
        .to(elements.title, { opacity: 1, duration: CONFIG.duration.fade })
        .to(elements.headers, { 
            opacity: 1, 
            stagger: 0.1, 
            duration: CONFIG.duration.fade 
        })
        .to({}, { duration: CONFIG.duration.pause });

    // ============================================
    // PHASE 1: PROJECT CREATION
    // ============================================
    
    tl.addLabel("projectCreation");
    
    // Show PROJECT CREATION banner
    animatePhaseIn(tl, "PROJECT CREATION", "project");
    
    tl.call(() => setCaption(CAPTIONS.projectCreate))
        .add(showNode(elements.originator.create))
        .call(() => highlightNode(elements.originator.create))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.projectRegister))
        .add(showNode(elements.core.register))
        .call(() => highlightNode(elements.core.register))
        .to({}, { duration: CONFIG.duration.pause });
    
    // Hide PROJECT CREATION banner
    animatePhaseOut(tl);

    // ============================================
    // PHASE 2: CONTRIBUTION
    // ============================================
    
    tl.addLabel("contribution");
    
    // Show CONTRIBUTION banner
    animatePhaseIn(tl, "CONTRIBUTION", "contribution");
    
    tl.call(() => setCaption(CAPTIONS.contributorClaim))
        .add(showNode(elements.contributor.claim))
        .call(() => highlightNode(elements.contributor.claim))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.contributorSubmit))
        .add(showNode(elements.contributor.submit))
        .call(() => highlightNode(elements.contributor.submit))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.enqueue))
        .add(showNode(elements.core.enqueue))
        .add(showNode(elements.oracle.queue), "<0.2")
        .to({}, { duration: CONFIG.duration.pause });
    
    // Hide CONTRIBUTION banner
    animatePhaseOut(tl);

    // ============================================
    // PHASE 3: COMMIT PHASE
    // ============================================
    
    tl.addLabel("commitPhase")
        .call(() => setCaption(CAPTIONS.validatorsClaim))
        .add(showNode(elements.v1.claim))
        .add(showNode(elements.v2.claim), "<0.15")
        .add(showNode(elements.v3.claim), "<0.15")
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.commitPhase));
    
    // Show COMMIT PHASE banner
    animatePhaseIn(tl, "COMMIT PHASE", "commit");
    
    tl.add(showNode(elements.oracle.collect))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.v1Commit))
        .add(showNode(elements.v1.commit))
        .call(() => highlightNode(elements.v1.commit))
        .to({}, { duration: 0.3 })
        
        .call(() => setCaption(CAPTIONS.v2Commit))
        .add(showNode(elements.v2.commit))
        .call(() => highlightNode(elements.v2.commit))
        .to({}, { duration: 0.3 })
        
        .call(() => setCaption(CAPTIONS.v3Commit))
        .add(showNode(elements.v3.commit))
        .call(() => highlightNode(elements.v3.commit))
        .to({}, { duration: CONFIG.duration.pause });
    
    // Hide COMMIT PHASE banner
    animatePhaseOut(tl);

    // ============================================
    // PHASE 4: REVEAL PHASE
    // ============================================
    
    tl.addLabel("revealPhase")
        .call(() => setCaption(CAPTIONS.revealPhase));
    
    // Show REVEAL PHASE banner
    animatePhaseIn(tl, "REVEAL PHASE", "reveal");
    
    tl.add(showNode(elements.oracle.reveals))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.v1Reveal))
        .add(showNode(elements.v1.reveal))
        .call(() => highlightNode(elements.v1.reveal))
        .to({}, { duration: 0.4 })
        
        .call(() => setCaption(CAPTIONS.v2Reveal))
        .add(showNode(elements.v2.reveal))
        .call(() => highlightNode(elements.v2.reveal))
        .to({}, { duration: 0.4 })
        
        .call(() => setCaption(CAPTIONS.v3Reveal))
        .add(showNode(elements.v3.reveal))
        .call(() => shakeNode(elements.v3.reveal))
        .to({}, { duration: CONFIG.duration.pause });
    
    // Hide REVEAL PHASE banner
    animatePhaseOut(tl);

    // ============================================
    // PHASE 5: CONSENSUS
    // ============================================
    
    tl.addLabel("consensusPhase")
        .call(() => setCaption(CAPTIONS.consensusPhase));
    
    // Show CONSENSUS banner
    animatePhaseIn(tl, "CONSENSUS", "consensus");
    
    tl.add(showNode(elements.oracle.calc))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.calcWeights))
        .add(showNode(elements.consensus.weights))
        .call(() => highlightNode(elements.consensus.weights))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.calcAverage))
        .add(showNode(elements.consensus.avg))
        .call(() => highlightNode(elements.consensus.avg))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.identifyOutliers))
        .add(showNode(elements.consensus.outliers))
        .call(() => highlightNode(elements.consensus.outliers))
        .to({}, { duration: CONFIG.duration.pause });
    
    // Hide CONSENSUS banner
    animatePhaseOut(tl);

    // ============================================
    // PHASE 6: OUTCOME
    // ============================================
    
    tl.addLabel("outcomePhase")
        .call(() => setCaption(CAPTIONS.outcomePhase));
    
    // Show OUTCOME banner
    animatePhaseIn(tl, "OUTCOME", "outcome");
    
    tl.add(showNode(elements.core.finalize))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.accepted))
        .add(showNode(elements.consensus.result))
        .call(() => highlightNode(elements.consensus.result))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.distributeRewards))
        .add(showNode(elements.core.distribute))
        .add(showNode(elements.v1.reward), "<0.2")
        .add(showNode(elements.v2.reward), "<0.2")
        .call(() => highlightNode(elements.v1.reward))
        .call(() => highlightNode(elements.v2.reward))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.slashOutlier))
        .add(showNode(elements.v3.slash))
        .call(() => shakeNode(elements.v3.slash))
        .to({}, { duration: CONFIG.duration.pause })
        
        .call(() => setCaption(CAPTIONS.contributorReward))
        .add(showNode(elements.contributor.reward))
        .call(() => highlightNode(elements.contributor.reward))
        .to({}, { duration: CONFIG.duration.pause });
    
    // Hide OUTCOME banner
    animatePhaseOut(tl);

    // ============================================
    // SUMMARY
    // ============================================
    
    tl.addLabel("summary")
        .call(() => setCaption(CAPTIONS.summary))
        .to({}, { duration: 2 });

    return tl;
}

// ============================================
// RESET FUNCTION
// ============================================

function resetAnimation() {
    // Reset all action nodes
    gsap.set('.action-node', { opacity: 0, scale: 0.8 });
    
    // Reset headers
    gsap.set('.actor-header', { opacity: 0 });
    
    // Reset title
    gsap.set(elements.title, { opacity: 0 });
    
    // Reset phase overlay - clear text and class
    gsap.set(elements.phaseOverlay, { opacity: 0, y: -20 });
    elements.phaseText.textContent = '';
    elements.phaseOverlay.className = 'phase-overlay';
    
    // Reset progress
    updateProgress(0);
    
    // Reset caption
    elements.captionText.textContent = "Click play to start the animation";
    
    // Kill and recreate timeline
    if (mainTimeline) {
        mainTimeline.kill();
    }
    mainTimeline = createTimeline();
}

// ============================================
// EVENT LISTENERS
// ============================================

elements.playBtn.addEventListener('click', () => {
    if (!mainTimeline) {
        mainTimeline = createTimeline();
    }
    
    if (isPlaying) {
        mainTimeline.pause();
        elements.playBtn.textContent = '▶ Play';
        isPlaying = false;
    } else {
        mainTimeline.play();
        elements.playBtn.textContent = '⏸ Pause';
        isPlaying = true;
    }
});

elements.restartBtn.addEventListener('click', () => {
    resetAnimation();
    isPlaying = false;
    elements.playBtn.textContent = '▶ Play';
    elements.playBtn.disabled = false;
});

// ============================================
// INITIALIZATION
// ============================================

document.addEventListener('DOMContentLoaded', () => {
    resetAnimation();
    console.log('Sapien Consensus Animation ready');
});
