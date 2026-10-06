-- Pure inheritance rules. `offspring` is a function of the two parents' snapshots and a stored
-- seed only, so the result of an egg is fixed the moment it is laid: leaving, rejoining or
-- releasing a parent cannot change it, and tests can recompute it exactly.
--
-- The random draws happen in a fixed order and every draw is always taken, whatever the branch,
-- so adding a rule later cannot silently reshuffle the draws for the rules before it.
local CreatureDefinitions = require("./CreatureDefinitions")
local GameConfig = require("../Config/GameConfig")
local MutationDefinitions = require("./MutationDefinitions")
local SeededRandom = require("../Util/SeededRandom")

local GENE_NAMES = table.freeze({ "vigor", "might", "focus" })

local GeneticsDomain = {}

GeneticsDomain.GENE_NAMES = GENE_NAMES

local function clampGene(value: number): number
    return math.max(GameConfig.GENE_MIN, math.min(GameConfig.GENE_MAX, value))
end

-- Multiplier on a worker's output from its vigor gene. A creature without genes (old data in a
-- test) counts as neutral.
function GeneticsDomain.vigorMultiplier(creature: any): number
    local genes = creature.genes
    if type(genes) ~= "table" or type(genes.vigor) ~= "number" then
        return 1
    end
    return 1 + (genes.vigor - GameConfig.NEUTRAL_GENE) * GameConfig.VIGOR_OUTPUT_PER_POINT
end

-- A parent snapshot as stored in an egg: only what inheritance needs.
function GeneticsDomain.snapshot(creature: any): any
    return {
        speciesId = creature.speciesId,
        generation = creature.generation,
        mutationId = creature.mutationId,
        genes = {
            vigor = creature.genes.vigor,
            might = creature.genes.might,
            focus = creature.genes.focus,
        },
    }
end

function GeneticsDomain.validSnapshot(snapshot: any): boolean
    if type(snapshot) ~= "table" or type(snapshot.speciesId) ~= "string" then
        return false
    end
    if CreatureDefinitions.ById[snapshot.speciesId] == nil then
        return false
    end
    if type(snapshot.generation) ~= "number" or snapshot.generation % 1 ~= 0 then
        return false
    end
    if snapshot.generation < 0 or type(snapshot.genes) ~= "table" then
        return false
    end
    for _, name in ipairs(GENE_NAMES) do
        local value = snapshot.genes[name]
        if
            type(value) ~= "number"
            or value % 1 ~= 0
            or value < GameConfig.GENE_MIN
            or value > GameConfig.GENE_MAX
        then
            return false
        end
    end
    return true
end

-- Seconds an egg takes to hatch: deeper lineages take longer, up to an hour.
function GeneticsDomain.hatchSeconds(parentA: any, parentB: any): number
    local generation = math.max(parentA.generation, parentB.generation)
    return math.min(
        GameConfig.BREEDING_HATCH_MAX_SECONDS,
        GameConfig.BREEDING_HATCH_BASE_SECONDS
            + generation * GameConfig.BREEDING_HATCH_PER_GENERATION_SECONDS
    )
end

-- What breeding `parentA` with `parentB` produces for this seed:
-- { speciesId, genes, mutationId?, generation, lineage }.
function GeneticsDomain.offspring(parentA: any, parentB: any, seed: number): any
    local random = SeededRandom.new(seed)

    -- Species. Two different base species may produce their hybrid; otherwise the baby takes
    -- after one parent. Hybrids and same-species pairs never produce a new hybrid.
    local hybridRoll = random:nextFloat()
    local parentRoll = random:nextFloat()
    local hybridId = CreatureDefinitions.hybridFor(parentA.speciesId, parentB.speciesId)
    local speciesId
    if hybridId ~= nil and hybridRoll < GameConfig.BREEDING_HYBRID_CHANCE then
        speciesId = hybridId
    elseif parentRoll < 0.5 then
        speciesId = parentA.speciesId
    else
        speciesId = parentB.speciesId
    end

    -- Genes: each from either parent, then a small drift.
    local genes = {}
    for _, name in ipairs(GENE_NAMES) do
        local fromA = random:nextFloat() < 0.5
        local drift =
            random:nextInt(-GameConfig.BREEDING_GENE_DRIFT, GameConfig.BREEDING_GENE_DRIFT)
        local inherited = if fromA then parentA.genes[name] else parentB.genes[name]
        genes[name] = clampGene(inherited + drift)
    end

    -- Mutation: rare, and picked by weight. Both draws are always taken.
    local mutationRoll = random:nextFloat()
    local weights = {}
    for _, id in ipairs(MutationDefinitions.Ids) do
        table.insert(weights, MutationDefinitions.ById[id].weight)
    end
    local mutationIndex = random:pickWeighted(weights)
    local mutationId = nil
    if mutationRoll < GameConfig.BREEDING_MUTATION_CHANCE then
        mutationId = MutationDefinitions.Ids[mutationIndex]
        local shift = MutationDefinitions.ById[mutationId].geneShift
        for _, name in ipairs(GENE_NAMES) do
            genes[name] = clampGene(genes[name] + shift[name])
        end
    end

    return {
        speciesId = speciesId,
        genes = genes,
        mutationId = mutationId,
        generation = math.min(
            GameConfig.BREEDING_MAX_GENERATION,
            math.max(parentA.generation, parentB.generation) + 1
        ),
        lineage = { speciesA = parentA.speciesId, speciesB = parentB.speciesId },
    }
end

return table.freeze(GeneticsDomain)
