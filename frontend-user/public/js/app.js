/**
 * 投标报价计算器 - 核心逻辑
 */
function bidCalculator() {
    return {
        // 配置参数
        config: {
            mode: 'single',        // 'single' 单低模式 | 'double' 双低模式
            maxPrice: null,        // 上限价（超出则废标）
            minPrice: null,        // 下限价（低于则废标）
            fullScore: 30,         // 价格分满分
            deductUp: 1.0,         // 上浮扣分系数（每高于基准价1%扣多少分）
            deductDown: 0.5,       // 下浮扣分系数（每低于基准价1%扣多少分，设为0表示低于不扣分）
            minScore: 0,           // 最低得分
            lowestWeight: 40,      // 双低模式下最低价权重(%)
        },
        
        // 投标报价列表
        bids: [],
        
        // 新增报价表单
        newBid: {
            name: '',
            price: null
        },
        
        // 报价ID计数器
        bidIdCounter: 0,

        // ========== 方案对比功能 ==========
        
        // 方案列表
        scenarios: [],
        
        // 当前选中的方案ID（null 表示当前编辑中的未保存方案）
        currentScenarioId: null,
        
        // 方案名称输入
        newScenarioName: '',
        
        // 对比模式开关
        compareMode: false,
        
        // 用于对比的方案ID列表
        compareScenarioIds: [],
        
        // 方案ID计数器
        scenarioIdCounter: 0,

        /**
         * 添加报价
         */
        addBid() {
            if (!this.newBid.name || !this.newBid.price || this.newBid.price <= 0) return;
            
            this.bids.push({
                id: ++this.bidIdCounter,
                name: this.newBid.name.trim(),
                price: parseFloat(this.newBid.price)
            });
            
            this.newBid = { name: '', price: null };
        },

        /**
         * 删除报价
         */
        removeBid(id) {
            this.bids = this.bids.filter(b => b.id !== id);
        },

        /**
         * 清空所有报价
         */
        clearBids() {
            this.bids = [];
            this.currentScenarioId = null;
        },

        // ========== 方案管理方法 ==========

        /**
         * 保存当前方案
         */
        saveScenario() {
            if (!this.newScenarioName.trim()) return;
            if (this.bids.length === 0) return;

            const scenarioData = {
                id: ++this.scenarioIdCounter,
                name: this.newScenarioName.trim(),
                config: JSON.parse(JSON.stringify(this.config)),
                bids: JSON.parse(JSON.stringify(this.bids)),
                bidIdCounter: this.bidIdCounter,
                createdAt: new Date().toISOString()
            };

            this.scenarios.push(scenarioData);
            this.currentScenarioId = scenarioData.id;
            this.newScenarioName = '';
        },

        /**
         * 更新当前方案
         */
        updateScenario() {
            if (!this.currentScenarioId) return;
            
            const scenario = this.scenarios.find(s => s.id === this.currentScenarioId);
            if (!scenario) return;

            scenario.config = JSON.parse(JSON.stringify(this.config));
            scenario.bids = JSON.parse(JSON.stringify(this.bids));
            scenario.bidIdCounter = this.bidIdCounter;
            scenario.updatedAt = new Date().toISOString();
        },

        /**
         * 加载方案
         */
        loadScenario(id) {
            const scenario = this.scenarios.find(s => s.id === id);
            if (!scenario) return;

            this.config = JSON.parse(JSON.stringify(scenario.config));
            this.bids = JSON.parse(JSON.stringify(scenario.bids));
            this.bidIdCounter = scenario.bidIdCounter;
            this.currentScenarioId = id;
            this.compareMode = false;
            this.compareScenarioIds = [];
        },

        /**
         * 删除方案
         */
        deleteScenario(id) {
            this.scenarios = this.scenarios.filter(s => s.id !== id);
            this.compareScenarioIds = this.compareScenarioIds.filter(sid => sid !== id);
            if (this.currentScenarioId === id) {
                this.currentScenarioId = null;
            }
            if (this.compareScenarioIds.length < 2) {
                this.compareMode = false;
            }
        },

        /**
         * 切换方案对比选择
         */
        toggleCompareScenario(id) {
            const index = this.compareScenarioIds.indexOf(id);
            if (index > -1) {
                this.compareScenarioIds.splice(index, 1);
            } else {
                if (this.compareScenarioIds.length < 4) {
                    this.compareScenarioIds.push(id);
                }
            }
            this.compareMode = this.compareScenarioIds.length >= 2;
        },

        /**
         * 获取方案的计算结果
         */
        getScenarioResults(scenario) {
            const tempConfig = this.config;
            const tempBids = this.bids;

            this.config = JSON.parse(JSON.stringify(scenario.config));
            this.bids = JSON.parse(JSON.stringify(scenario.bids));

            const results = {
                scenarioId: scenario.id,
                scenarioName: scenario.name,
                config: scenario.config,
                baselinePrice: this.baselinePrice,
                validBidsCount: this.validBidsCount,
                lowestValidPrice: this.lowestValidPrice,
                averageValidPrice: this.averageValidPrice,
                sortedResults: this.sortedResults
            };

            this.config = tempConfig;
            this.bids = tempBids;

            return results;
        },

        /**
         * 获取对比的所有方案结果
         */
        get compareResults() {
            return this.compareScenarioIds.map(id => {
                const scenario = this.scenarios.find(s => s.id === id);
                return scenario ? this.getScenarioResults(scenario) : null;
            }).filter(Boolean);
        },

        /**
         * 获取所有投标人名称（用于对比表格）
         */
        get allBidderNames() {
            const names = new Set();
            this.compareResults.forEach(result => {
                result.sortedResults.forEach(r => names.add(r.name));
            });
            return Array.from(names);
        },

        /**
         * 获取投标人在指定方案中的数据
         */
        getBidderData(bidderName, scenarioResult) {
            return scenarioResult.sortedResults.find(r => r.name === bidderName);
        },

        /**
         * 导出方案数据
         */
        exportScenarios() {
            const data = {
                scenarios: this.scenarios,
                exportedAt: new Date().toISOString()
            };
            const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `报价方案_${new Date().toLocaleDateString()}.json`;
            a.click();
            URL.revokeObjectURL(url);
        },

        /**
         * 导入方案数据
         */
        importScenarios(event) {
            const file = event.target.files[0];
            if (!file) return;

            const reader = new FileReader();
            reader.onload = (e) => {
                try {
                    const data = JSON.parse(e.target.result);
                    if (data.scenarios && Array.isArray(data.scenarios)) {
                        data.scenarios.forEach(scenario => {
                            scenario.id = ++this.scenarioIdCounter;
                            this.scenarios.push(scenario);
                        });
                    }
                } catch (err) {
                    console.error('导入失败:', err);
                }
            };
            reader.readAsText(file);
            event.target.value = '';
        },

        /**
         * 检查报价是否有效（限价判断）
         * - 超过上限价 → 废标
         * - 低于下限价 → 废标
         */
        checkValidity(price) {
            if (this.config.maxPrice !== null && this.config.maxPrice !== '' && price > this.config.maxPrice) {
                return { valid: false, reason: '超上限' };
            }
            if (this.config.minPrice !== null && this.config.minPrice !== '' && price < this.config.minPrice) {
                return { valid: false, reason: '低下限' };
            }
            return { valid: true, reason: '' };
        },

        /**
         * 获取所有有效报价
         */
        get validBids() {
            return this.bids.filter(bid => this.checkValidity(bid.price).valid);
        },

        /**
         * 有效报价数量
         */
        get validBidsCount() {
            return this.validBids.length;
        },

        /**
         * 最低有效报价
         */
        get lowestValidPrice() {
            if (this.validBids.length === 0) return null;
            return Math.min(...this.validBids.map(b => b.price));
        },

        /**
         * 有效报价平均值
         */
        get averageValidPrice() {
            if (this.validBids.length === 0) return null;
            const sum = this.validBids.reduce((acc, b) => acc + b.price, 0);
            return sum / this.validBids.length;
        },

        /**
         * 计算评标基准价
         * - 单低模式：基准价 = 最低有效报价
         * - 双低模式：基准价 = 最低有效价 × A% + 平均有效价 × B%
         */
        get baselinePrice() {
            if (this.validBids.length === 0) return null;
            
            if (this.config.mode === 'single') {
                return this.lowestValidPrice;
            } else {
                const lowestWeight = this.config.lowestWeight / 100;
                const avgWeight = 1 - lowestWeight;
                return this.lowestValidPrice * lowestWeight + this.averageValidPrice * avgWeight;
            }
        },

        /**
         * 计算偏离率
         * 偏离率 = (报价 - 基准价) / 基准价 × 100%
         * 正值表示高于基准价，负值表示低于基准价
         */
        calculateDeviation(price) {
            if (!this.baselinePrice) return 0;
            return ((price - this.baselinePrice) / this.baselinePrice) * 100;
        },

        /**
         * 计算扣分
         * - 报价 > 基准价：扣分 = 偏离率 × 上浮扣分系数
         * - 报价 < 基准价：扣分 = |偏离率| × 下浮扣分系数
         * - 报价 = 基准价：扣分 = 0
         */
        calculateDeduction(price) {
            if (!this.baselinePrice) return 0;
            
            const deviation = this.calculateDeviation(price);
            
            if (deviation > 0) {
                return deviation * this.config.deductUp;
            } else if (deviation < 0) {
                return Math.abs(deviation) * this.config.deductDown;
            }
            return 0;
        },

        /**
         * 计算最终得分
         * 得分 = 满分 - 扣分
         * 最终得分不低于最低得分限制
         */
        calculateScore(price) {
            if (!this.baselinePrice) return 0;
            
            const deduction = this.calculateDeduction(price);
            let score = this.config.fullScore - deduction;
            
            score = Math.max(score, this.config.minScore);
            score = Math.min(score, this.config.fullScore);
            
            return score;
        },

        /**
         * 排序后的结果（按得分降序）
         */
        get sortedResults() {
            const results = this.bids.map(bid => {
                const validity = this.checkValidity(bid.price);
                const isValid = validity.valid;
                
                return {
                    id: bid.id,
                    name: bid.name,
                    price: bid.price,
                    isValid: isValid,
                    invalidReason: validity.reason,
                    deviation: isValid ? this.calculateDeviation(bid.price) : 0,
                    deduction: isValid ? this.calculateDeduction(bid.price) : 0,
                    score: isValid ? this.calculateScore(bid.price) : 0
                };
            });

            // 排序：有效报价在前，按得分降序；无效报价在后
            results.sort((a, b) => {
                if (a.isValid && !b.isValid) return -1;
                if (!a.isValid && b.isValid) return 1;
                if (!a.isValid && !b.isValid) return 0;
                if (b.score !== a.score) return b.score - a.score;
                return a.price - b.price;
            });

            // 添加排名（同分同名次）
            let rank = 0;
            let lastScore = null;
            let skipCount = 0;
            
            results.forEach((r, i) => {
                if (r.isValid) {
                    if (r.score !== lastScore) {
                        rank = rank + 1 + skipCount;
                        skipCount = 0;
                    } else {
                        skipCount++;
                    }
                    r.rank = rank;
                    lastScore = r.score;
                } else {
                    r.rank = null;
                }
            });

            return results;
        }
    }
}
