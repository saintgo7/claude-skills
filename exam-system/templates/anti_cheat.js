/**
 * Anti-cheat client helpers for exam mode.
 *
 * Expected globals on the host page:
 *   isExamMode          — boolean
 *   isPrivileged        — boolean (professor/admin: skip all restrictions)
 *   quizSubmitted       — boolean
 *   tabSwitchCount      — number (shared counter)
 *   submitQuiz(auto)    — function
 *   showExamWarning(msg)— function (toast)
 *
 * Host should call enableExamAntiCheat() when the exam goes ACTIVE
 * and disableExamAntiCheat() right before showing results.
 */

function enableExamAntiCheat() {
    if (isPrivileged) return;

    // 1. Block text selection via CSS class on <body>
    document.body.classList.add('exam-no-select');

    // 2. Block copy/cut/paste and right-click
    document.addEventListener('copy', examPreventCopy);
    document.addEventListener('cut', examPreventCopy);
    document.addEventListener('paste', examPreventCopy);
    document.addEventListener('contextmenu', examPreventCopy);

    // 3. Block keyboard shortcuts (DevTools / View-source / Copy-all / Save)
    document.addEventListener('keydown', examPreventKeys);

    // 4. Tab-switch detection (3-strike auto-submit)
    document.addEventListener('visibilitychange', examTabDetect);

    // 5. Fullscreen enforcement
    requestExamFullscreen();
    document.addEventListener('fullscreenchange', examFullscreenChange);
    document.addEventListener('webkitfullscreenchange', examFullscreenChange);
}

function disableExamAntiCheat() {
    document.body.classList.remove('exam-no-select');
    document.removeEventListener('copy', examPreventCopy);
    document.removeEventListener('cut', examPreventCopy);
    document.removeEventListener('paste', examPreventCopy);
    document.removeEventListener('contextmenu', examPreventCopy);
    document.removeEventListener('keydown', examPreventKeys);
    document.removeEventListener('visibilitychange', examTabDetect);
    document.removeEventListener('fullscreenchange', examFullscreenChange);
    document.removeEventListener('webkitfullscreenchange', examFullscreenChange);
}

function examPreventCopy(e) {
    if (isExamMode && !quizSubmitted && !isPrivileged) {
        e.preventDefault();
        showExamWarning('Copy/paste is disabled during the exam.');
    }
}

function examPreventKeys(e) {
    if (!isExamMode || quizSubmitted || isPrivileged) return;
    // Ctrl/Cmd + C, V, A, U, S
    if ((e.ctrlKey || e.metaKey) && ['c','v','a','u','s'].includes(e.key.toLowerCase())) {
        e.preventDefault();
        showExamWarning('Shortcut blocked during the exam.');
        return;
    }
    // Ctrl/Cmd + Shift + I / J / C  → DevTools
    if ((e.ctrlKey || e.metaKey) && e.shiftKey && ['i','j','c'].includes(e.key.toLowerCase())) {
        e.preventDefault();
        showExamWarning('Developer tools are blocked.');
        return;
    }
    if (e.key === 'F12') {
        e.preventDefault();
        showExamWarning('Developer tools are blocked.');
    }
}

function examTabDetect() {
    if (!isExamMode || quizSubmitted || isPrivileged) return;
    if (document.hidden) {
        tabSwitchCount++;
        if (tabSwitchCount >= 3) {
            showExamWarning('Tab switched 3 times — auto-submitting.');
            setTimeout(() => submitQuiz(true), 1500);
        } else {
            showExamWarning('Warning: do not switch tabs (' + tabSwitchCount + '/3).');
        }
    }
}

function requestExamFullscreen() {
    const el = document.documentElement;
    try {
        if (el.requestFullscreen) el.requestFullscreen();
        else if (el.webkitRequestFullscreen) el.webkitRequestFullscreen();
    } catch (err) {
        // Fullscreen API may be blocked without user gesture; that's fine.
    }
}

function examFullscreenChange() {
    if (!isExamMode || quizSubmitted || isPrivileged) return;
    const inFs = document.fullscreenElement || document.webkitFullscreenElement;
    if (!inFs) {
        showExamWarning('Please remain in fullscreen during the exam.');
    }
}

/**
 * Deterministic Lehmer-style shuffle. Given the same (arr, seed), always produces
 * the same permutation. Use seed = user_id * 10000 + quiz_id for question order,
 * and seed + question_id for option order.
 */
function deterministicShuffle(arr, seed) {
    const a = [...arr];
    let s = seed;
    for (let i = a.length - 1; i > 0; i--) {
        s = (s * 1103515245 + 12345) & 0x7fffffff;
        const j = s % (i + 1);
        [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
}
