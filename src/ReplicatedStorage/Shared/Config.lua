-- Shared configuration values for the whole game.
-- These values are safe to read on both server and client.

return {
    -- Fruit spawn settings
    MAX_FRUITS = 8,
    SPAWN_INTERVAL = 1.5,

    -- Fruit values
    DEFAULT_FRUIT_SELL_PRICE = 5,

    -- Map size (used for random fruit spawning)
    MAP_MIN_X = -40,
    MAP_MAX_X = 40,
    MAP_MIN_Z = -40,
    MAP_MAX_Z = 40,

    -- Spawn height above the ground
    SPAWN_Y = 2,

    -- Optional place to add DataStore later
    -- DATASTORE_NAME = "FruitCollectorData",
}
