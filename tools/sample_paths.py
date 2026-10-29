"""Where each example of docs/samples/ keeps its data, for the generators and converters of tools/."""
import os


# Where an example keeps its data — by default the "3D models" one. The six generators wrote these two
# lines each, and moving the models into model_3d/ therefore took six identical edits — the next move
# would take six more, with one generator liable to stay behind and write beside the catalogue.
def sample_path(name, folder="model_3d"):
    root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    return os.path.join(root, "docs", "samples", folder, name)
