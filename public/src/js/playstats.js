class PlayStats {
    constructor() {
        this.cache = {}
    }

    // 获取歌曲的游玩统计
    async get(hash) {
        if (this.cache[hash]) {
            return this.cache[hash]
        }
        try {
            const response = await fetch(`api/playcount/get?hash=${encodeURIComponent(hash)}`)
            const data = await response.json()
            if (data.status === 'ok') {
                this.cache[hash] = {
                    playCount: data.play_count,
                    weeklyHighScore: data.weekly_high_score
                }
                return this.cache[hash]
            }
        } catch (e) {
            console.error('Failed to fetch play stats:', e)
        }
        return null
    }

    // 记录一次游玩
    async record(hash, difficulty, score, isAuto) {
        try {
            const token = await loader.getCsrfToken()
            await fetch('api/playcount/record', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRFToken': token
                },
                body: JSON.stringify({
                    hash: hash,
                    difficulty: difficulty,
                    score: score,
                    is_auto: isAuto
                })
            })
            // 清除缓存以便下次获取新数据
            delete this.cache[hash]
        } catch (e) {
            console.error('Failed to record play:', e)
        }
    }
}

var playStats = new PlayStats()
