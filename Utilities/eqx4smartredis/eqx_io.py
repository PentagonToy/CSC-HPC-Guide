# eqx_io.py
# Source: source /scratch/project_2015384/Hanseul/Utilities/environmentSetup.sh
# Install: pip install -e /scratch/project_2015384/Hanseul/Utilities/eqx4smartredis 
# Install: pip install -e .
# Uninstall: /scratch/project_2015384/Hanseul/Utilities/Python/envs/PentagonToy-3.11/bin/python -m pip uninstall -y eqx_io

import equinox as eqx
import jax
import jax.numpy as jnp
import numpy as np
import json
from pathlib import Path


def serialize_model(model, transport_dtype=np.float32):
    """Equinox model -> (flat_array, meta_json)

    Works with any Equinox module (MLP, CNN, Transformer, etc.)
    by flattening all array leaves into a single buffer.

    Args:
        model: Equinox module to serialize.
        transport_dtype: numpy dtype for the flat buffer sent over the wire.
            Use np.float64 to preserve full precision of float64 parameters.
            Original per-leaf dtypes are always stored in metadata
            and restored during deserialization.
    """
    params = eqx.filter(model, eqx.is_array)
    flat_leaves, tree_def = jax.tree_util.tree_flatten(params)

    shapes = [list(p.shape) for p in flat_leaves]
    dtypes = [str(p.dtype) for p in flat_leaves]
    meta = json.dumps({"shapes": shapes, "dtypes": dtypes})

    flat_array = np.concatenate([np.array(p).ravel() for p in flat_leaves])
    return flat_array.astype(transport_dtype), meta


def deserialize_model(flat_array, meta_json, model_template):
    """Reconstruct an Equinox model from flat_array + meta.

    model_template must have the same architecture (same pytree structure).
    Original per-leaf dtypes are restored from metadata.
    """
    meta = json.loads(meta_json)
    shapes = meta["shapes"]
    dtypes = meta["dtypes"]

    params_template = eqx.filter(model_template, eqx.is_array)
    _, tree_def = jax.tree_util.tree_flatten(params_template)

    flat_params = []
    offset = 0
    for shape, dtype_str in zip(shapes, dtypes):
        size = int(np.prod(shape))
        p = jnp.array(flat_array[offset:offset + size], dtype=dtype_str).reshape(shape)
        flat_params.append(p)
        offset += size

    new_params = jax.tree_util.tree_unflatten(tree_def, flat_params)
    static = eqx.filter(model_template, lambda x: not eqx.is_array(x))
    return eqx.combine(new_params, static)


def upload_model_to_db(client, model, epoch, prefix="model",
                       transport_dtype=np.float32):
    """Upload serialized model weights + metadata to SmartRedis.

    Args:
        client: SmartRedis Client instance.
        model: Equinox module to upload.
        epoch: epoch number or label (e.g. "best").
        prefix: key prefix in the database.
        transport_dtype: numpy dtype for the flat weight buffer.
            Use np.float64 to preserve full precision.
    """
    flat_array, meta_json = serialize_model(model, transport_dtype=transport_dtype)
    client.put_tensor(f"{prefix}_weights_epoch_{epoch}", flat_array)

    meta_bytes = np.frombuffer(meta_json.encode("utf-8"), dtype=np.uint8)
    client.put_tensor(f"{prefix}_meta", meta_bytes)


def download_model_from_db(client, model_template, epoch, prefix="model"):
    """Download and reconstruct model from SmartRedis.

    The transport dtype is handled automatically — per-leaf dtypes
    are restored from the stored metadata regardless of the buffer dtype.
    """
    flat_array = client.get_tensor(f"{prefix}_weights_epoch_{epoch}")
    meta_bytes = client.get_tensor(f"{prefix}_meta")
    meta_json = bytes(meta_bytes).decode("utf-8")
    return deserialize_model(flat_array, meta_json, model_template)


# ── Disk I/O ──────────────────────────────────────────────────────────

def save_model(model, path, config=None):
    """Save an Equinox model to disk.

    Saves weights as .eqx and optionally a config dict as .json
    so the model can be fully reconstructed later.

    Args:
        model: Equinox module.
        path: file path (e.g. "checkpoints/model_final.eqx").
            Config will be saved alongside as <stem>_config.json.
        config: optional dict with architecture info (hidden_dims, activation, etc.).
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    eqx.tree_serialise_leaves(path, model)

    if config is not None:
        config_path = path.with_name(f"{path.stem}_config.json")
        with open(config_path, "w") as f:
            json.dump(config, f, indent=2)

    print(f"[eqx_io] Model saved to {path}"
          + (f" (config: {config_path})" if config else ""))


def load_model(path, model_template):
    """Load an Equinox model from disk.

    Args:
        path: path to .eqx file.
        model_template: an Equinox module with identical architecture
            (weights will be overwritten).

    Returns:
        Restored Equinox model.
    """
    path = Path(path)
    model = eqx.tree_deserialise_leaves(path, model_template)
    print(f"[eqx_io] Model loaded from {path}")
    return model
