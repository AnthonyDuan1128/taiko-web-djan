/**
 * Dan-i Dojo (段位道場) Exam Manager
 * Tracks exam conditions during Dan mode gameplay
 */
class DanExam {
    constructor(exams, danSongs) {
        // Exam conditions: [{type, red, gold, scope}, ...]
        // type: g=gauge/accuracy%, jp=good hits, jb=bad hits, r=drumroll hits
        // scope: m=merge (overall), l=less (per-song limit)
        this.exams = exams || []
        this.danSongs = danSongs || []
        this.currentSongIndex = 0

        // Stats tracking
        this.stats = {
            totalNotes: 0,
            goodHits: 0,      // 良 (perfect)
            okHits: 0,        // 可 (ok)
            badHits: 0,       // 不可 (miss)
            drumrollHits: 0,  // 連打 (drumroll)
            maxCombo: 0,
            currentCombo: 0
        }

        // Per-song stats for scope=l exams
        this.perSongStats = []
        this.resetSongStats()
    }

    resetSongStats() {
        this.currentSongStats = {
            goodHits: 0,
            okHits: 0,
            badHits: 0,
            drumrollHits: 0
        }
    }

    /**
     * Called when moving to next song in Dan exam
     */
    nextSong() {
        this.perSongStats.push({ ...this.currentSongStats })
        this.resetSongStats()
        this.currentSongIndex++
    }

    /**
     * Record a hit result
     * @param {string} result - 'good', 'ok', 'bad', 'drumroll'
     * @param {number} count - number of hits (usually 1, but drumroll can be higher)
     */
    recordHit(result, count = 1) {
        switch (result) {
            case 'good':
                this.stats.goodHits += count
                this.currentSongStats.goodHits += count
                this.stats.currentCombo += count
                if (this.stats.currentCombo > this.stats.maxCombo) {
                    this.stats.maxCombo = this.stats.currentCombo
                }
                break
            case 'ok':
                this.stats.okHits += count
                this.currentSongStats.okHits += count
                this.stats.currentCombo += count
                if (this.stats.currentCombo > this.stats.maxCombo) {
                    this.stats.maxCombo = this.stats.currentCombo
                }
                break
            case 'bad':
                this.stats.badHits += count
                this.currentSongStats.badHits += count
                this.stats.currentCombo = 0
                break
            case 'drumroll':
                this.stats.drumrollHits += count
                this.currentSongStats.drumrollHits += count
                break
        }
    }

    /**
     * Set total note count for accuracy calculation
     */
    setTotalNotes(count) {
        this.stats.totalNotes = count
    }

    /**
     * Get current accuracy percentage (gauge)
     */
    getAccuracy() {
        var total = this.stats.goodHits + this.stats.okHits + this.stats.badHits
        if (total === 0) return 100
        // 良=100%, 可=50%, 不可=0%
        var score = this.stats.goodHits * 100 + this.stats.okHits * 50
        return score / total
    }

    /**
     * Check exam condition status
     * @param {Object} exam - {type, red, gold, scope}
     * @returns {Object} - {status: 'gold'|'red'|'fail', current, target}
     */
    checkExam(exam) {
        var current = 0
        var isLowerBetter = false

        switch (exam.type) {
            case 'g': // gauge/accuracy %
                current = this.getAccuracy()
                break
            case 'jp': // good hits (良)
            case 'h':  // total good hits (良の数) - same as jp
                current = exam.scope === 'l'
                    ? this.currentSongStats.goodHits
                    : this.stats.goodHits
                break
            case 'jb': // bad hits (不可) - lower is better
                current = exam.scope === 'l'
                    ? this.currentSongStats.badHits
                    : this.stats.badHits
                isLowerBetter = true
                break
            case 'r': // drumroll hits
                current = exam.scope === 'l'
                    ? this.currentSongStats.drumrollHits
                    : this.stats.drumrollHits
                break
        }

        var status = 'fail'
        if (isLowerBetter) {
            // For "bad hits", lower is better (gold < red)
            if (current <= exam.gold) {
                status = 'gold'
            } else if (current <= exam.red) {
                status = 'red'
            }
        } else {
            // For most conditions, higher is better (gold > red)
            if (current >= exam.gold) {
                status = 'gold'
            } else if (current >= exam.red) {
                status = 'red'
            }
        }

        return {
            status: status,
            current: current,
            redTarget: exam.red,
            goldTarget: exam.gold,
            type: exam.type,
            scope: exam.scope,
            isLowerBetter: isLowerBetter
        }
    }

    /**
     * Get status of all exams
     */
    getAllExamStatus() {
        return this.exams.map(exam => ({
            exam: exam,
            result: this.checkExam(exam)
        }))
    }

    /**
     * Check if passed (all exams at least red level)
     */
    isPassed() {
        return this.exams.every(exam => {
            var result = this.checkExam(exam)
            return result.status !== 'fail'
        })
    }

    /**
     * Check if gold pass (all exams at gold level)
     */
    isGoldPass() {
        return this.exams.every(exam => {
            var result = this.checkExam(exam)
            return result.status === 'gold'
        })
    }

    /**
     * Get overall result
     */
    getResult() {
        if (this.isGoldPass()) return 'gold'
        if (this.isPassed()) return 'pass'
        return 'fail'
    }

    /**
     * Get exam type display name
     */
    static getExamTypeName(type) {
        switch (type) {
            case 'g': return '魂ゲージ'   // Soul gauge
            case 'jp': return '良'        // Good
            case 'h': return '良の数'     // Good hit count
            case 'jb': return '不可'      // Bad
            case 'r': return '連打'       // Drumroll
            case 'c': return 'コンボ'     // Max combo
            default: return type
        }
    }
}
