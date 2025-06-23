#!/bin/bash
# ------------------------------- SLURM Header ------------------------------- #
#SBATCH  --job-name=srvz3018-ray-cluster    # Job name
#SBATCH  --time=00:05:00                    # Request runtime (hh:mm:ss)
#SBATCH --output=slurm-%j.ans             # Output file (%j = job ID)

# ---------------------------- Multithreaded Tasks --------------------------- #
#SBATCH  --cpus-per-task=4                  # Number of CPU cores per task
#SBATCH --mem-per-cpu=4G
##SBATCH  --mem=32G                         # Total memory for the job

# ------------------- Parallel Tasks Multiprocessing Tasks ------------------- #
##SBATCH  --ntasks=1                         # Number of code to be executed in parallel when using mpirun code or srun code

# - Message Passing Interface (MPI) for  jobs that run across multiple nodes - #
#SBATCH  --nodes=3                          # Request n node
#SBATCH  --ntasks-per-node=1                # Number of code to be executed in parallel on 1 node when using mpirun code or srun code

# --------------------------------- GPU Tasks -------------------------------- #
##SBATCH  --partition=gpu                    # Request GPU partition
##SBATCH  --gres=gpu:1                       # Request 1 GPU


# ------------------------------ Parallel Tasks ------------------------------ #
module load openmpi
# ---------------------------- Multithreaded Tasks --------------------------- #
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK # Tell OpenMP how many resources it has been given

conda deactivate
source ~/.bashrc
module load miniforge
conda activate robodiff

# Expand the node list
echo "Obtain the allocated node information..."
nodes=($(scontrol show hostnames $SLURM_NODELIST))
export head_node=${nodes[0]}
worker_nodes=("${nodes[@]:1}")

echo "Node list: $SLURM_NODELIST"
echo "Head node: $head_node"
echo "Worker nodes: ${worker_nodes[@]}"

# 获取 head 节点 IP（运行在 head 节点上）
echo "Starting Ray Configuration..."
export ray_port=6379
srun --nodes=1 --nodelist=$head_node --ntasks=1 --output=outputs/head.ans \
    bash -c '
        ray_head_ip=$(hostname --ip-address)
        echo "Starting Ray head on $HOSTNAME (${ray_head_ip}:${ray_port})..."

        num_cpus=$SLURM_CPUS_PER_TASK
        num_gpus=$(echo $CUDA_VISIBLE_DEVICES | awk -F"," '\''{print NF}'\'')

        echo "Number of CPUs on head: $num_cpus"
        echo "Number of GPUs on head: $num_gpus"

        ray start --head \
                  --node-ip-address="$ray_head_ip" \
                  --port=${ray_port} \
                  --num-cpus="$num_cpus" \
                  --num-gpus="$num_gpus" \
                  --block \

    ' &

# # 遍历每个 worker 节点启动 Ray worker
for node in "${worker_nodes[@]}"; do
    export node
    echo "Starting Ray worker on ${node} ..."
    srun --nodes=1 --nodelist=$node --ntasks=1 --output=outputs/work_$node.ans \
        bash -c '
            echo "Starting Ray worker on $node ..."

            num_cpus=$SLURM_CPUS_PER_TASK
            num_gpus=$(echo $CUDA_VISIBLE_DEVICES | awk -F"," '\''{print NF}'\'')

            ray start --address='"$head_node:$ray_port"' \
                    --num-cpus="$num_cpus" \
                    --num-gpus="$num_gpus" \
                    --resources='{}' \
                    --block \
        ' &
done


# # ------------------- 执行 Ray 程序 ------------------- #

echo "Submitting Ray job..."

python work.py -m hydra.launcher.ray.init.address=${head_node}:${ray_port}
