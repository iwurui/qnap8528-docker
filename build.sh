#!/bin/bash

# 定义变量
IMAGE_NAME="kernel-compiler"
CONTAINER_NAME="kernel-compiler"
SOURCE_CODE_DIR="./src"
# 通过 uname -r 获取内核版本
KERNEL_VERSION=$(uname -r)
KERNEL_HEADERS_DIR="/usr/src/linux-headers-$KERNEL_VERSION"

# 检查镜像是否存在
if docker images -q $IMAGE_NAME | grep -q .; then
    read -p "镜像 $IMAGE_NAME 已存在，是否重新构建镜像？(y/n): " rebuild_choice
    case $rebuild_choice in
        [Yy])
            echo "正在构建 Docker 镜像..."
            docker build -t $IMAGE_NAME -f Dockerfile .
            if [ $? -ne 0 ]; then
                echo "镜像构建失败，请检查 Dockerfile。"
                exit 1
            fi
            ;;
        [Nn])
            echo "使用现有镜像。"
            ;;
        *)
            echo "无效的选项，退出脚本。"
            exit 1
            ;;
    esac
else
    # 镜像不存在，构建 Docker 镜像
    echo "镜像 $IMAGE_NAME 不存在，开始构建 Docker 镜像..."
    docker build -t $IMAGE_NAME -f Dockerfile .
    if [ $? -ne 0 ]; then
        echo "镜像构建失败，请检查 Dockerfile。"
        exit 1
    fi
fi

# 检查容器是否已存在
if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    echo "容器 $CONTAINER_NAME 已存在，正在删除..."
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
fi

# 运行 Docker 容器
echo "正在启动 Docker 容器..."
docker run -itd \
    --name $CONTAINER_NAME \
    -v $SOURCE_CODE_DIR:/driver \
    -v $KERNEL_HEADERS_DIR:/usr/src/linux-headers-$KERNEL_VERSION \
    $IMAGE_NAME bash

if [ $? -ne 0 ]; then
    echo "容器启动失败，请检查配置。"
    exit 1
fi

echo "容器已成功启动。"
echo "正在创建软链接..."
docker exec -it $CONTAINER_NAME bash -c "mkdir -p /lib/modules/$KERNEL_VERSION && ln -s /usr/src/linux-headers-$KERNEL_VERSION /lib/modules/$KERNEL_VERSION/build"

echo "正在进入容器并执行编译命令..."
docker exec -it $CONTAINER_NAME bash -c "cd /driver && make -C /lib/modules/$KERNEL_VERSION/build M=\$PWD modules"

if [ $? -ne 0 ]; then
    echo "编译失败，请检查代码和配置。"
    exit 1
else
    echo "编译成功！"
    echo "退出容器"
    # 复制驱动文件到宿主机指定目录
    DRIVER_DIR="/lib/modules/$KERNEL_VERSION/extra"
    if [ ! -d "$DRIVER_DIR" ]; then
        echo "创建 $DRIVER_DIR 目录"
        sudo mkdir -p $DRIVER_DIR
    fi
    echo "复制驱动文件到 $DRIVER_DIR"
    sudo cp $SOURCE_CODE_DIR/*.ko $DRIVER_DIR
    # 刷新依赖
    echo "刷新依赖"
    sudo depmod -a
    # 加载驱动
    DRIVER_NAME=$(basename $SOURCE_CODE_DIR/*.ko .ko)
    echo "加载驱动 $DRIVER_NAME"
    sudo modprobe $DRIVER_NAME
    # 配置开机自动加载
    echo "配置开机自动加载驱动 $DRIVER_NAME"
    echo $DRIVER_NAME | sudo tee -a /etc/modules-load.d/$DRIVER_NAME.conf > /dev/null

    # 删除容器
    echo "正在删除容器 $CONTAINER_NAME..."
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
fi

# 运行 sensors 命令并截取 qnap8528 传感器数据
echo "运行 sensors 命令并截取 qnap8528 传感器数据"
sensors_output=$(sensors)
qnap8528_data=$(echo "$sensors_output" | awk '/qnap8528/,/^$/' | sed '/^$/d')
if [ -n "$qnap8528_data" ]; then
    echo "qnap8528 传感器数据如下："
    echo "$qnap8528_data"
else
    echo "未找到 qnap8528 传感器数据。"
fi
