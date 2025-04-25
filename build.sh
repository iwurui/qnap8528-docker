#!/bin/bash

# 定义变量
IMAGE_NAME="kernel-compiler"
CONTAINER_NAME="kernel-compiler"
SOURCE_CODE_DIR="./src"
# 通过 uname -r 获取内核版本
KERNEL_VERSION=$(uname -r)
KERNEL_HEADERS_DIR="/usr/src/linux-headers-$KERNEL_VERSION"

# 检查容器是否已存在
if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
    echo "容器 $CONTAINER_NAME 已存在，请选择操作："
    echo "1. 删除该容器重新构建镜像"
    echo "2. 直接启动该容器"
    echo "3. 退出"
    read -p "请输入选项编号: " choice
    case $choice in
        1)
            echo "正在删除容器 $CONTAINER_NAME..."
            docker stop $CONTAINER_NAME
            docker rm $CONTAINER_NAME
            # 构建 Docker 镜像
            echo "正在构建 Docker 镜像..."
            docker build -t $IMAGE_NAME -f Dockerfile .
            if [ $? -ne 0 ]; then
                echo "镜像构建失败，请检查 Dockerfile。"
                exit 1
            fi
            ;;
        2)
            ;;
        3)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效的选项，退出脚本。"
            exit 1
            ;;
    esac
else
    # 容器不存在，构建 Docker 镜像
    echo "容器 $CONTAINER_NAME 不存在，开始构建 Docker 镜像..."
    docker build -t $IMAGE_NAME -f Dockerfile .
    if [ $? -ne 0 ]; then
        echo "镜像构建失败，请检查 Dockerfile。"
        exit 1
    fi
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
fi

echo "编译成功！"
