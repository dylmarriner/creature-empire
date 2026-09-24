local NumberUtil = {}

function NumberUtil.isFiniteNumber(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function NumberUtil.isInteger(value: any): boolean
    return NumberUtil.isFiniteNumber(value) and value % 1 == 0
end

function NumberUtil.isNonNegativeInteger(value: any): boolean
    return NumberUtil.isInteger(value) and value >= 0
end

function NumberUtil.isPositiveInteger(value: any): boolean
    return NumberUtil.isInteger(value) and value > 0
end

return table.freeze(NumberUtil)
