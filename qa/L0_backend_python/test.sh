#!/bin/bash
# Copyright (c) 2020-2021, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

CLIENT_PY=./python_test.py
CLIENT_LOG="./client.log"
EXPECTED_NUM_TESTS="10"

SERVER=/opt/tritonserver/bin/tritonserver
BASE_SERVER_ARGS="--model-repository=`pwd`/models --log-verbose=1"
PYTHON_BACKEND_BRANCH=$PYTHON_BACKEND_REPO_TAG
SERVER_ARGS=$BASE_SERVER_ARGS
SERVER_LOG="./inference_server.log"
REPO_VERSION=${NVIDIA_TRITON_SERVER_VERSION}
DATADIR=${DATADIR:="/data/inferenceserver/${REPO_VERSION}"}
source ../common/util.sh

get_shm_pages() {
  shm_pages=(`ls /dev/shm`)
  echo ${#shm_pages[@]}
}

install_conda() {
  rm -rf ./miniconda
  file_name="Miniconda3-py38_4.9.2-Linux-x86_64.sh"
  wget https://repo.anaconda.com/miniconda/$file_name

  # install miniconda in silent mode
  bash $file_name -p ./miniconda -b

  # activate conda
  eval "$(./miniconda/bin/conda shell.bash hook)"
}

create_conda_env() {
  python_version=$1
  env_name=$2
  conda create -n $env_name python=$python_version -y
  conda activate $env_name
  conda install conda-pack -y
}

create_python_backend_stub() {
  rm -rf python_backend
  git clone https://github.com/triton-inference-server/python_backend -b $PYTHON_BACKEND_BRANCH
  (cd python_backend/ && mkdir builddir && cd builddir && \
  cmake -DTRITON_BACKEND_REPO_TAG=$TRITON_BACKEND_REPO_TAG -DTRITON_COMMON_REPO_TAG=$TRITON_COMMON_REPO_TAG -DTRITON_CORE_REPO_TAG=$TRITON_CORE_REPO_TAG ../ && \
  make -j18 triton-python-backend-stub)
}

rm -fr *.log ./models

mkdir -p models/identity_fp32/1/
cp ../python_models/identity_fp32/model.py ./models/identity_fp32/1/model.py
cp ../python_models/identity_fp32/config.pbtxt ./models/identity_fp32/config.pbtxt

cp -r ./models/identity_fp32 ./models/identity_uint8
(cd models/identity_uint8 && \
          sed -i "s/^name:.*/name: \"identity_uint8\"/" config.pbtxt && \
          sed -i "s/TYPE_FP32/TYPE_UINT8/g" config.pbtxt && \
          sed -i "s/^max_batch_size:.*/max_batch_size: 8/" config.pbtxt && \
          echo "dynamic_batching { preferred_batch_size: [8], max_queue_delay_microseconds: 12000000 }" >> config.pbtxt)

cp -r ./models/identity_fp32 ./models/identity_uint8_nobatch
(cd models/identity_uint8_nobatch && \
          sed -i "s/^name:.*/name: \"identity_uint8_nobatch\"/" config.pbtxt && \
          sed -i "s/TYPE_FP32/TYPE_UINT8/g" config.pbtxt && \
          sed -i "s/^max_batch_size:.*//" config.pbtxt >> config.pbtxt)

cp -r ./models/identity_fp32 ./models/identity_uint32
(cd models/identity_uint32 && \
          sed -i "s/^name:.*/name: \"identity_uint32\"/" config.pbtxt && \
          sed -i "s/TYPE_FP32/TYPE_UINT32/g" config.pbtxt)

cp -r ./models/identity_fp32 ./models/identity_bool
(cd models/identity_bool && \
          sed -i "s/^name:.*/name: \"identity_bool\"/" config.pbtxt && \
          sed -i "s/TYPE_FP32/TYPE_BOOL/g" config.pbtxt)

mkdir -p models/wrong_model/1/
cp ../python_models/wrong_model/model.py ./models/wrong_model/1/
cp ../python_models/wrong_model/config.pbtxt ./models/wrong_model/
(cd models/wrong_model && \
          sed -i "s/^name:.*/name: \"wrong_model\"/" config.pbtxt && \
          sed -i "s/TYPE_FP32/TYPE_UINT32/g" config.pbtxt)

mkdir -p models/pytorch_fp32_fp32/1/
cp -r ../python_models/pytorch_fp32_fp32/model.py ./models/pytorch_fp32_fp32/1/
cp ../python_models/pytorch_fp32_fp32/config.pbtxt ./models/pytorch_fp32_fp32/
(cd models/pytorch_fp32_fp32 && \
          sed -i "s/^name:.*/name: \"pytorch_fp32_fp32\"/" config.pbtxt)

mkdir -p models/execute_error/1/
cp ../python_models/execute_error/model.py ./models/execute_error/1/
cp ../python_models/execute_error/config.pbtxt ./models/execute_error/
(cd models/execute_error && \
          sed -i "s/^name:.*/name: \"execute_error\"/" config.pbtxt && \
          sed -i "s/^max_batch_size:.*/max_batch_size: 8/" config.pbtxt && \
          echo "dynamic_batching { preferred_batch_size: [8], max_queue_delay_microseconds: 12000000 }" >> config.pbtxt)

mkdir -p models/init_args/1/
cp ../python_models/init_args/model.py ./models/init_args/1/
cp ../python_models/init_args/config.pbtxt ./models/init_args/

# Ensemble Model
mkdir -p models/ensemble/1/
cp ../python_models/ensemble/config.pbtxt ./models/ensemble

mkdir -p models/add_sub_1/1/
cp ../python_models/add_sub/config.pbtxt ./models/add_sub_1
(cd models/add_sub_1 && \
          sed -i "s/^name:.*/name: \"add_sub_1\"/" config.pbtxt)
cp ../python_models/add_sub/model.py ./models/add_sub_1/1/

mkdir -p models/add_sub_2/1/
cp ../python_models/add_sub/config.pbtxt ./models/add_sub_2/
(cd models/add_sub_2 && \
          sed -i "s/^name:.*/name: \"add_sub_2\"/" config.pbtxt)
cp ../python_models/add_sub/model.py ./models/add_sub_2/1/

# Ensemble GPU Model
mkdir -p models/ensemble_gpu/1/
cp ../python_models/ensemble_gpu/config.pbtxt ./models/ensemble_gpu
cp -r ${DATADIR}/qa_model_repository/libtorch_float32_float32_float32/ ./models
(cd models/libtorch_float32_float32_float32 && \
          echo "instance_group [ { kind: KIND_GPU }]" >> config.pbtxt)
(cd models/libtorch_float32_float32_float32 && \
          sed -i "s/^max_batch_size:.*/max_batch_size: 0/" config.pbtxt)
(cd models/libtorch_float32_float32_float32 && \
          sed -i "s/^version_policy:.*//" config.pbtxt)
rm -rf models/libtorch_float32_float32_float32/2
rm -rf models/libtorch_float32_float32_float32/3

# Unicode Characters
mkdir -p models/string/1/
cp ../python_models/string/model.py ./models/string/1/
cp ../python_models/string/config.pbtxt ./models/string

# More string tests
mkdir -p models/string_fixed/1/
cp ../python_models/string_fixed/model.py ./models/string_fixed/1/
cp ../python_models/string_fixed/config.pbtxt ./models/string_fixed

pip3 install torch==1.6.0+cpu torchvision==0.7.0+cpu -f https://download.pytorch.org/whl/torch_stable.html

prev_num_pages=`get_shm_pages`
run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi

RET=0

set +e
python3 $CLIENT_PY >>$CLIENT_LOG 2>&1
if [ $? -ne 0 ]; then
    RET=1
else
    check_test_results $CLIENT_LOG $EXPECTED_NUM_TESTS
    if [ $? -ne 0 ]; then
        cat $CLIENT_LOG
        echo -e "\n***\n*** Test Result Verification Failed\n***"
        RET=1
    fi
fi
set -e

kill $SERVER_PID
wait $SERVER_PID
sleep 4

current_num_pages=`get_shm_pages`
if [ $current_num_pages -ne $prev_num_pages ]; then
    ls /dev/shm
    cat $CLIENT_LOG
    echo -e "\n***\n*** Test Failed. Shared memory pages where not cleaned properly.
Shared memory pages before starting triton equals to $prev_num_pages
and shared memory pages after starting triton equals to $current_num_pages \n***"
    RET=1
fi

prev_num_pages=`get_shm_pages`
# Triton non-graceful exit
run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi

sleep 5

triton_procs=`pgrep --parent $SERVER_PID`

set +e

# Trigger non-graceful termination of Triton
kill -9 $SERVER_PID

# Wait 10 seconds so that Python stub can detect non-graceful exit
sleep 10

for triton_proc in $triton_procs; do
    kill -0 $triton_proc > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        cat $CLIENT_LOG
        echo -e "\n***\n*** Python backend non-graceful exit test failed \n***"
        RET=1
        break
    fi
done
set -e

current_num_pages=`get_shm_pages`
if [ $current_num_pages -ne $prev_num_pages ]; then
    cat $CLIENT_LOG
    ls /dev/shm
    echo -e "\n***\n*** Test Failed. Shared memory pages where not cleaned properly.
Shared memory pages before starting triton equals to $prev_num_pages
and shared memory pages after starting triton equals to $current_num_pages \n***"
    RET=1
fi

# These models have errors in the initialization and finalization
# steps and we want to ensure that correct error is being returned

rm -rf models/
mkdir -p models/init_error/1/
cp ../python_models/init_error/model.py ./models/init_error/1/
cp ../python_models/init_error/config.pbtxt ./models/init_error/

set +e
prev_num_pages=`get_shm_pages`
run_server_nowait

wait $SERVER_PID
current_num_pages=`get_shm_pages`
if [ $current_num_pages -ne $prev_num_pages ]; then
    cat $CLIENT_LOG
    ls /dev/shm
    echo -e "\n***\n*** Test Failed. Shared memory pages where not cleaned properly.
Shared memory pages before starting triton equals to $prev_num_pages
and shared memory pages after starting triton equals to $current_num_pages \n***"
    RET=1
fi

grep "name 'lorem_ipsum' is not defined" $SERVER_LOG

if [ $? -ne 0 ]; then
    cat $CLIENT_LOG
    echo -e "\n***\n*** init_error model test failed \n***"
    RET=1
fi
set -e

rm -rf models/
mkdir -p models/fini_error/1/
cp ../python_models/fini_error/model.py ./models/fini_error/1/
cp ../python_models/fini_error/config.pbtxt ./models/fini_error/

set +e
prev_num_pages=`get_shm_pages`
run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi
set -e

kill $SERVER_PID
wait $SERVER_PID
sleep 5

current_num_pages=`get_shm_pages`
if [ $current_num_pages -ne $prev_num_pages ]; then
    cat $CLIENT_LOG
    ls /dev/shm
    echo -e "\n***\n*** Test Failed. Shared memory pages where not cleaned properly.
Shared memory pages before starting triton equals to $prev_num_pages
and shared memory pages after starting triton equals to $current_num_pages \n***"
    exit 1
fi

set +e
grep "name 'undefined_variable' is not defined" $SERVER_LOG

if [ $? -ne 0 ]; then
    cat $CLIENT_LOG
    echo -e "\n***\n*** fini_error model test failed \n***"
    RET=1
fi
set -e

set +e
# Test KIND_GPU
rm -rf models/
mkdir -p models/add_sub_gpu/1/
cp ../python_models/add_sub/model.py ./models/add_sub_gpu/1/
cp ../python_models/add_sub_gpu/config.pbtxt ./models/add_sub_gpu/

prev_num_pages=`get_shm_pages`
run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi

if [ $? -ne 0 ]; then
    cat $SERVER_LOG
    echo -e "\n***\n*** KIND_GPU model test failed \n***"
    RET=1
fi
set -e

kill $SERVER_PID
wait $SERVER_PID
sleep 5

current_num_pages=`get_shm_pages`
if [ $current_num_pages -ne $prev_num_pages ]; then
    cat $CLIENT_LOG
    ls /dev/shm
    echo -e "\n***\n*** Test Failed. Shared memory pages where not cleaned properly.
Shared memory pages before starting triton equals to $prev_num_pages
and shared memory pages after starting triton equals to $current_num_pages \n***"
    exit 1
fi

# Test Multi file models
rm -rf models/
mkdir -p models/multi_file/1/
cp ../python_models/multi_file/*.py ./models/multi_file/1/
cp ../python_models/identity_fp32/config.pbtxt ./models/multi_file/
(cd models/multi_file && \
          sed -i "s/^name:.*/name: \"multi_file\"/" config.pbtxt)

set +e
prev_num_pages=`get_shm_pages`
run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi

if [ $? -ne 0 ]; then
    cat $SERVER_LOG
    echo -e "\n***\n*** multi-file model test failed \n***"
    RET=1
fi

set +e
kill $SERVER_PID
wait $SERVER_PID
sleep 5
set -e

current_num_pages=`get_shm_pages`
if [ $current_num_pages -ne $prev_num_pages ]; then
    cat $SERVER_LOG
    ls /dev/shm
    echo -e "\n***\n*** Test Failed. Shared memory pages where not cleaned properly.
Shared memory pages before starting triton equals to $prev_num_pages
and shared memory pages after starting triton equals to $current_num_pages \n***"
    exit 1
fi

# Test environment variable propagation
rm -rf models/
mkdir -p models/model_env/1/
cp ../python_models/model_env/model.py ./models/model_env/1/
cp ../python_models/model_env/config.pbtxt ./models/model_env/

export MY_ENV="MY_ENV"
prev_num_pages=`get_shm_pages`
run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    echo -e "\n***\n*** Environment variable test failed \n***"
    cat $SERVER_LOG
    exit 1
fi
set +e

kill $SERVER_PID
wait $SERVER_PID
sleep 5

current_num_pages=`get_shm_pages`
if [ $current_num_pages -ne $prev_num_pages ]; then
    cat $CLIENT_LOG
    ls /dev/shm
    echo -e "\n***\n*** Test Failed. Shared memory pages where not cleaned properly.
Shared memory pages before starting triton equals to $prev_num_pages
and shared memory pages after starting triton equals to $current_num_pages \n***"
    exit 1
fi

rm -fr ./models
mkdir -p models/identity_fp32/1/
cp ../python_models/identity_fp32/model.py ./models/identity_fp32/1/model.py
cp ../python_models/identity_fp32/config.pbtxt ./models/identity_fp32/config.pbtxt

shm_default_byte_size=$((1024*1024*4))
SERVER_ARGS="$BASE_SERVER_ARGS --backend-config=python,shm-default-byte-size=$shm_default_byte_size"

run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi

for shm_page in `ls /dev/shm/`; do
    page_size=`ls -l /dev/shm/$shm_page 2>&1 | awk '{print $5}'`
    if [ $page_size -ne $shm_default_byte_size ]; then
        echo -e "Shared memory region size is not equal to
$shm_default_byte_size for page $shm_page. Region size is
$page_size."
        RET=1
    fi
done
set +e

kill $SERVER_PID
wait $SERVER_PID
sleep 5

rm -fr ./models
rm -rf *.tar.gz
apt update && apt install software-properties-common rapidjson-dev -y
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
	gpg --dearmor - |  \
	tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null && \
	apt-add-repository 'deb https://apt.kitware.com/ubuntu/ focal main' && \
	apt-get update && \
	apt-get install -y --no-install-recommends \
	cmake-data=3.18.4-0kitware1ubuntu20.04.1 cmake=3.18.4-0kitware1ubuntu20.04.1
install_conda

# Create a model with python 3.9 version
create_conda_env "3.9" "python-3-9"
conda install numpy=1.20.1 -y
create_python_backend_stub
conda-pack -o python3.9.tar.gz
path_to_conda_pack=`pwd`/python3.9.tar.gz
mkdir -p models/python_3_9/1/
cp ../python_models/python_version/config.pbtxt ./models/python_3_9
(cd models/python_3_9 && \
          sed -i "s/^name:.*/name: \"python_3_9\"/" config.pbtxt && \
          echo "parameters: {key: \"EXECUTION_ENV_PATH\", value: {string_value: \"$path_to_conda_pack\"}}">> config.pbtxt)
cp ../python_models/python_version/model.py ./models/python_3_9/1/
cp python_backend/builddir/triton_python_backend_stub ./models/python_3_9
conda deactivate

# Create a model with python 3.6 version
create_conda_env "3.6" "python-3-6"
conda install numpy=1.18.1 -y
conda-pack -o python3.6.tar.gz
path_to_conda_pack=`pwd`/python3.6.tar.gz
create_python_backend_stub
mkdir -p models/python_3_6/1/
cp ../python_models/python_version/config.pbtxt ./models/python_3_6
(cd models/python_3_6 && \
          sed -i "s/^name:.*/name: \"python_3_6\"/" config.pbtxt && \
          echo "parameters: {key: \"EXECUTION_ENV_PATH\", value: {string_value: \"$path_to_conda_pack\"}}" >> config.pbtxt)
cp ../python_models/python_version/model.py ./models/python_3_6/1/
cp python_backend/builddir/triton_python_backend_stub ./models/python_3_6

run_server
if [ "$SERVER_PID" == "0" ]; then
    echo -e "\n***\n*** Failed to start $SERVER\n***"
    cat $SERVER_LOG
    exit 1
fi
set +e

kill $SERVER_PID
wait $SERVER_PID
sleep 5

grep "Python version is 3.6 and NumPy version is 1.18.1" $SERVER_LOG
if [ $? -ne 0 ]; then
    cat $SERVER_LOG
    echo -e "\n***\n*** Python 3.6 and NumPy 1.18.1 was not found in Triton logs. \n***"
    RET=1
fi

grep "Python version is 3.9 and NumPy version is 1.20.1" $SERVER_LOG
if [ $? -ne 0 ]; then
    cat $SERVER_LOG
    echo -e "\n***\n*** Python 3.9 and NumPy 1.20.1 was not found in Triton logs. \n***"
    RET=1
fi
set -e

if [ $RET -eq 0 ]; then
  echo -e "\n***\n*** Test Passed\n***"
else
    cat $SERVER_LOG
    echo -e "\n***\n*** Test FAILED\n***"
fi

exit $RET

