extends Node3D
## Generates a simple ground plane for vehicle physics testing.

func _ready() -> void:
    # Ground plane
    var ground := StaticBody3D.new()
    ground.name = "Ground"
    add_child(ground)

    var mesh_instance := MeshInstance3D.new()
    var plane_mesh := PlaneMesh.new()
    plane_mesh.size = Vector2(500, 500)
    plane_mesh.subdivide_width = 50
    plane_mesh.subdivide_depth = 50
    mesh_instance.mesh = plane_mesh

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.25, 0.25, 0.28)
    material.roughness = 0.8
    mesh_instance.material_override = material
    ground.add_child(mesh_instance)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(500, 0.1, 500)
    collision.shape = shape
    collision.position.y = -0.05
    ground.add_child(collision)
