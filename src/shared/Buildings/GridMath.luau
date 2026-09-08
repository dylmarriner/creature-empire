local GridMath = {}

local function isFinite(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

function GridMath.snapCoordinate(value: number, gridSize: number): number
    assert(isFinite(value), "value must be finite")
    assert(isFinite(gridSize) and gridSize > 0, "gridSize must be a positive finite number")

    return math.round(value / gridSize) * gridSize
end

function GridMath.snapPosition(
    position: { x: number, y: number, z: number },
    gridSize: number
): { x: number, y: number, z: number }
    return {
        x = GridMath.snapCoordinate(position.x, gridSize),
        y = GridMath.snapCoordinate(position.y, gridSize),
        z = GridMath.snapCoordinate(position.z, gridSize),
    }
end

return table.freeze(GridMath)
