#include <libproc.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

static int receive(int fd) {
    char token;
    return read(fd, &token, 1) == 1;
}

static int measure(pid_t pid, struct rusage_info_v4 *usage) {
    return proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)usage);
}

int main(int argc, char **argv) {
    if (argc > 2 || (argc == 2 && strcmp(argv[1], "--exec"))) return 2;
    int replaceExecutable = argc == 2;
    const size_t bytes = 64 * 1024 * 1024;
    int commands[2], replies[2];
    if (pipe(commands) || pipe(replies)) return 1;
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) {
        close(commands[1]);
        close(replies[0]);
        if (!receive(commands[0])) _exit(2);
        volatile char *memory = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (memory == MAP_FAILED) _exit(3);
        for (size_t offset = 0; offset < bytes; offset += getpagesize()) memory[offset] = 1;
        write(replies[1], "a", 1);
        if (!receive(commands[0])) _exit(2);
        if (munmap((void *)memory, bytes)) _exit(4);
        write(replies[1], "f", 1);
        if (!receive(commands[0])) _exit(2);
        if (replaceExecutable) {
            execl("/bin/sleep", "sleep", "2", NULL);
            _exit(5);
        }
        _exit(0);
    }
    close(commands[0]);
    close(replies[1]);
    struct rusage_info_v4 before = {0}, held = {0}, released = {0};
    int failed = measure(child, &before);
    write(commands[1], "a", 1);
    if (!receive(replies[0])) failed = 1;
    failed |= measure(child, &held);
    write(commands[1], "f", 1);
    if (!receive(replies[0])) failed = 1;
    failed |= measure(child, &released);
    write(commands[1], "x", 1);
    struct rusage_info_v4 afterExec = {0};
    if (replaceExecutable) {
        int replaced = 0;
        for (int attempt = 0; attempt < 100; attempt++) {
            char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
            if (proc_pidpath(child, path, sizeof(path)) > 0 && !strcmp(path, "/bin/sleep")) {
                replaced = 1;
                break;
            }
            usleep(10000);
        }
        failed |= !replaced;
        failed |= measure(child, &afterExec);
    }
    close(commands[1]);
    close(replies[0]);
    int status;
    waitpid(child, &status, 0);
    if (failed || !WIFEXITED(status) || WEXITSTATUS(status)) return 1;
    printf("{\"allocation_bytes\":%zu,\"before_current\":%llu,\"before_peak\":%llu,"
           "\"held_current\":%llu,\"held_peak\":%llu,\"released_current\":%llu,\"released_peak\":%llu",
           bytes, before.ri_phys_footprint, before.ri_lifetime_max_phys_footprint,
           held.ri_phys_footprint, held.ri_lifetime_max_phys_footprint,
           released.ri_phys_footprint, released.ri_lifetime_max_phys_footprint);
    if (replaceExecutable) {
        printf(",\"after_exec_current\":%llu,\"after_exec_peak\":%llu,\"same_birth\":%s",
               afterExec.ri_phys_footprint, afterExec.ri_lifetime_max_phys_footprint,
               afterExec.ri_proc_start_abstime == before.ri_proc_start_abstime ? "true" : "false");
    }
    puts("}");
    return 0;
}
