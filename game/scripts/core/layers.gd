class_name Layers
## Physics layer bits.

const STATIC := 1        # anchored voxel structures, terrain
const DYNAMIC := 2       # free voxel bodies
const DEBRIS := 4        # tiny debris cubes
const PLAYER := 8
const PROJECTILE := 16

const SOLID := STATIC | DYNAMIC
