#!/bin/bash
# Patches author: weishu <twsxtd@gmail.com>
# Shell authon: xiaoleGun <1592501605@qq.com>
#               bdqllW <bdqllT@gmail.com>
# Tested kernel versions: 5.4, 4.19, 4.14, 4.9
# 20240123

patch_files=(
    fs/exec.c
    fs/open.c
    fs/read_write.c
    fs/stat.c
    drivers/input/input.c
    fs/namei.c
)

# 添加path_umount回移植功能
if ! grep -q "static int path_umount" fs/namespace.c; then
    echo "Adding path_umount to fs/namespace.c"
    sed -i '/int umount_tree/i\
static int path_umount(struct path *path, int flags)\n\
{\n\
\tstruct mount *mnt = real_mount(path->mnt);\n\
\n\
\tif (!check_mnt(mnt))\n\
\t\treturn -EINVAL;\n\
\n\
\treturn umount_tree(mnt, flags);\n\
}\n\
EXPORT_SYMBOL(path_umount);\n\
\n\
' fs/namespace.c
fi

for i in "${patch_files[@]}"; do

    if grep -q "ksu" "$i"; then
        echo "Warning: $i contains KernelSU"
        continue
    fi

    case $i in

    # fs/ changes
    ## exec.c
    fs/exec.c)
        sed -i '/static int do_execveat_common/i\#ifdef CONFIG_KSU\nextern bool ksu_execveat_hook __read_mostly;\nextern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\n			void *envp, int *flags);\nextern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,\n				 void *argv, void *envp, int *flags);\n#endif' fs/exec.c
        if grep -q "return __do_execve_file(fd, filename, argv, envp, flags, NULL);" fs/exec.c; then
            sed -i '/return __do_execve_file(fd, filename, argv, envp, flags, NULL);/i\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_execveat_hook))\n		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n	else\n		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\n	#endif' fs/exec.c
        else
            sed -i '/if (IS_ERR(filename))/i\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_execveat_hook))\n		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n	else\n		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\n	#endif' fs/exec.c
        fi
        ;;

    ## open.c
    fs/open.c)
        if grep -q "long do_faccessat(int dfd, const char __user \*filename, int mode)" fs/open.c; then
            sed -i '/long do_faccessat(int dfd, const char __user \*filename, int mode)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\n			 int *flags);\n#endif' fs/open.c
        else
            sed -i '/SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\n			 int *flags);\n#endif' fs/open.c
        fi
        sed -i '/if (mode & ~S_IRWXO)/i\	#ifdef CONFIG_KSU\n	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n	#endif\n' fs/open.c
        ;;

    ## read_write.c
    fs/read_write.c)
        sed -i '/ssize_t vfs_read(struct file/i\#ifdef CONFIG_KSU\nextern bool ksu_vfs_read_hook __read_mostly;\nextern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,\n		size_t *count_ptr, loff_t **pos);\n#endif' fs/read_write.c
        sed -i '/ssize_t vfs_read(struct file/,/ssize_t ret;/{/ssize_t ret;/a\
        #ifdef CONFIG_KSU\
        if (unlikely(ksu_vfs_read_hook))\
            ksu_handle_vfs_read(&file, &buf, &count, &pos);\
        #endif
        }' fs/read_write.c
        ;;

    ## stat.c
    fs/stat.c)
        if grep -q "int vfs_statx(int dfd, const char __user \*filename, int flags," fs/stat.c; then
            sed -i '/int vfs_statx(int dfd, const char __user \*filename, int flags,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n#endif' fs/stat.c
            sed -i '/unsigned int lookup_flags = LOOKUP_FOLLOW | LOOKUP_AUTOMOUNT;/a\\n	#ifdef CONFIG_KSU\n	ksu_handle_stat(&dfd, &filename, &flags);\n	#endif' fs/stat.c
        else
            sed -i '/int vfs_fstatat(int dfd, const char __user \*filename, struct kstat \*stat,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n#endif\n' fs/stat.c
            sed -i '/if ((flag & ~(AT_SYMLINK_NOFOLLOW | AT_NO_AUTOMOUNT |/i\	#ifdef CONFIG_KSU\n	ksu_handle_stat(&dfd, &filename, &flag);\n	#endif\n' fs/stat.c
        fi
        ;;

    ## namei.c - 为SukiSU添加挂载点处理
    fs/namei.c)
        if ! grep -q "ksu_handle_path_mount" fs/namei.c; then
            sed -i '/#include <linux\/mount.h>/a\#ifdef CONFIG_KSU\nextern int ksu_handle_path_mount(const char __user *dir_name, int *flags);\n#endif' fs/namei.c
            if grep -q "static int path_mount" fs/namei.c; then
                sed -i '/static int path_mount/,/^{/a\\n\t#ifdef CONFIG_KSU\n\tif (ksu_handle_path_mount(dir_name, flags) == 0)\n\t\treturn 0;\n\t#endif' fs/namei.c
            fi
        fi
        ;;

    # drivers/input changes
    ## input.c
    drivers/input/input.c)
        sed -i '/static void input_handle_event/i\#ifdef CONFIG_KSU\nextern bool ksu_input_hook __read_mostly;\nextern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\n#endif\n' drivers/input/input.c
        sed -i '/int disposition = input_get_disposition(dev, type, code, &value);/a\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_input_hook))\n		ksu_handle_input_handle_event(&type, &code, &value);\n	#endif' drivers/input/input.c
        ;;
    esac

done

# 确保添加相关头文件并导出符号
echo "Making sure to add needed headers for path_umount"
if ! grep -q "#include <linux/path.h>" fs/namespace.c; then
    sed -i '1i\#include <linux/path.h>' fs/namespace.c
fi

# 在内核头文件中声明path_umount函数
echo "Declaring path_umount in kernel headers"

# 尝试从不同路径查找可能的头文件位置
possible_header_paths=(
    "include/linux/fs.h"
    "include/linux/mount.h"
    "include/linux/fs_struct.h"
    "include/linux/namespace.h" 
)

# 查找合适的头文件添加声明
for header in "${possible_header_paths[@]}"; do
    if [ -f "$header" ]; then
        if ! grep -q "path_umount" "$header"; then
            echo "Adding path_umount declaration to $header"
            if grep -q "struct path" "$header"; then
                sed -i '/struct path/a\extern int path_umount(struct path *path, int flags);' "$header"
                break
            elif grep -q "struct mount" "$header"; then
                sed -i '/struct mount/a\extern int path_umount(struct path *path, int flags);' "$header"
                break
            else
                sed -i '1i\#ifndef _PATH_UMOUNT_EXPORTED\n#define _PATH_UMOUNT_EXPORTED\nstruct path;\nextern int path_umount(struct path *path, int flags);\n#endif' "$header"
                break
            fi
        else
            echo "path_umount already declared in $header"
            break
        fi
    fi
done