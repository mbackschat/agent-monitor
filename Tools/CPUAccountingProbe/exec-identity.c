#include <bsm/libbsm.h>
#include <errno.h>
#include <libproc.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

struct observation {
    int resource_result;
    struct rusage_info_v4 usage;
    struct proc_bsdinfo bsd;
    int bsd_bytes;
    kern_return_t port_result;
    kern_return_t token_result;
    int pidversion;
    mach_port_t port;
};

static int receive(int fd) {
    char byte;
    return read(fd, &byte, 1) == 1 ? byte : -1;
}

static void allocate_memory(size_t bytes) {
    volatile char *memory = malloc(bytes);
    if (!memory) _exit(3);
    for (size_t index = 0; index < bytes; index += 4096) memory[index] = 1;
}

static kern_return_t token(mach_port_t port, int *version) {
    audit_token_t value = {{0}};
    mach_msg_type_number_t count = TASK_AUDIT_TOKEN_COUNT;
    kern_return_t result = task_info(port, TASK_AUDIT_TOKEN, (task_info_t)&value, &count);
    if (result == KERN_SUCCESS) *version = audit_token_to_pidversion(value);
    return result;
}

static struct observation observe(pid_t pid) {
    struct observation value = {0};
    value.pidversion = -1;
    value.resource_result = proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&value.usage);
    value.bsd_bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &value.bsd, sizeof(value.bsd));
    value.port_result = task_name_for_pid(mach_task_self(), pid, &value.port);
    value.token_result = value.port_result == KERN_SUCCESS
        ? token(value.port, &value.pidversion) : value.port_result;
    return value;
}

static void print_observation(struct observation value) {
    char uuid[33];
    for (int index = 0; index < 16; index++) snprintf(uuid + 2 * index, 3, "%02x", value.usage.ri_uuid[index]);
    printf("{\"resource_result\":%d,\"bsd_bytes\":%d,\"birth_abstime\":%llu,"
           "\"uuid\":\"%s\",\"name\":\"%s\",\"peak\":%llu,\"cpu_ticks\":%llu,"
           "\"task_name_result\":%d,\"audit_token_result\":%d,\"pidversion\":%d}",
           value.resource_result, value.bsd_bytes, value.usage.ri_proc_start_abstime,
           uuid, value.bsd.pbi_comm, value.usage.ri_lifetime_max_phys_footprint,
           value.usage.ri_user_time + value.usage.ri_system_time,
           value.port_result, value.token_result, value.pidversion);
}

int main(int argc, char **argv) {
    if (argc == 4 && !strcmp(argv[1], "after")) {
        int gate = atoi(argv[2]), reply = atoi(argv[3]);
        const char *phase = getenv("AGENT_MONITOR_EXEC_PROBE");
        if (!phase || strcmp(phase, "after")) return 4;
        allocate_memory(32 * 1024 * 1024);
        if (write(reply, "a", 1) != 1 || receive(gate) != 'x') return 5;
        return 0;
    }
    if (argc != 1) return 2;
    int commands[2], replies[2];
    if (pipe(commands) || pipe(replies)) return 1;
    pid_t child = fork();
    if (child < 0) return 1;
    if (!child) {
        close(commands[1]);
        close(replies[0]);
        if (setenv("AGENT_MONITOR_EXEC_PROBE", "before", 1)) _exit(4);
        allocate_memory(16 * 1024 * 1024);
        if (write(replies[1], "b", 1) != 1 || receive(commands[0]) != 'e') _exit(5);
        if (setenv("AGENT_MONITOR_EXEC_PROBE", "after", 1)) _exit(4);
        char gate[20], reply[20];
        snprintf(gate, sizeof(gate), "%d", commands[0]);
        snprintf(reply, sizeof(reply), "%d", replies[1]);
        execl(argv[0], argv[0], "after", gate, reply, NULL);
        _exit(6);
    }
    close(commands[0]);
    close(replies[1]);
    int failed = receive(replies[0]) != 'b';
    struct observation before = observe(child);
    if (write(commands[1], "e", 1) != 1) failed = 1;
    if (receive(replies[0]) != 'a') failed = 1;
    struct observation after = observe(child);
    int retained_version = -1;
    kern_return_t retained_result = before.port_result == KERN_SUCCESS
        ? token(before.port, &retained_version) : before.port_result;
    if (write(commands[1], "x", 1) != 1) failed = 1;
    close(commands[1]);
    close(replies[0]);
    int status = 0;
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status)) failed = 1;
    printf("{\"protocol_ok\":%s,\"before\":", failed ? "false" : "true");
    print_observation(before);
    printf(",\"after\":");
    print_observation(after);
    printf(",\"retained_audit_result\":%d,\"retained_pidversion\":%d}\n", retained_result, retained_version);
    if (before.port != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), before.port);
    if (after.port != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), after.port);
    return failed ? 1 : 0;
}
