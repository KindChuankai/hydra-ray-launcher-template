import os
import ray
import hydra
from omegaconf import OmegaConf
from omegaconf import DictConfig
import socket
import time



# allows arbitrary python code execution in configs using the ${eval:''} resolver
OmegaConf.register_new_resolver("eval", eval, replace=True)
# allows environment variable access in configs using the ${env:} resolver
OmegaConf.register_new_resolver("env", lambda k: os.environ.get(k, ""))

@ray.remote(
    num_cpus=2,
    num_gpus=0,
    max_retries=2,
    resources={},
    retry_exceptions=True
)
def write_cfg_to_file(cfg_dict, cwd):
    lr = cfg_dict["model"]["lr"]
    hidden = cfg_dict["model"]["hidden"]
    filename = f"lr={lr}_hidden={hidden}.txt"
    path = os.path.join(cwd,"outputs", filename)
    with open(path, "w") as f:
        f.write(f"Learning rate: {lr}\n")
        f.write(f"Hidden size: {hidden}\n")
    return path

@hydra.main(version_base=None, config_path=".", config_name="config.yaml")
def main(cfg: DictConfig):

    OmegaConf.resolve(cfg)

    hostname = socket.gethostname()
    print("Current hostname:", hostname)

    # ray.init(address="auto")  # hydra-ray-launcher will handle this
    cfg_dict = OmegaConf.to_container(cfg, resolve=True)
    cwd = os.getcwd()
    print("Current working directory:", cwd)
    result = ray.get(write_cfg_to_file.remote(cfg_dict, cwd))


if __name__ == "__main__":
    main()
