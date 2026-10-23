#include <mach/mach.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int main(void) {
    int gate[2];
    if (pipe(gate)) return 1;
    pid_t pid = fork();
    if (pid < 0) return 1;
    if (pid == 0) {
        close(gate[1]);
        char token;
        if (read(gate[0], &token, 1) != 1) _exit(2);
        uint64_t start = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID);
        while (clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - start < 100000000) {}
        _exit(0);
    }
    close(gate[0]);
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t acquired = task_name_for_pid(mach_task_self(), pid, &port);
    task_absolutetime_info_data_t info = {0};
    mach_msg_type_number_t count = TASK_ABSOLUTETIME_INFO_COUNT;
    kern_return_t before = acquired == KERN_SUCCESS
        ? task_info(port, TASK_ABSOLUTETIME_INFO, (task_info_t)&info, &count) : acquired;
    write(gate[1], "x", 1);
    close(gate[1]);
    waitpid(pid, NULL, 0);
    info = (task_absolutetime_info_data_t){0};
    count = TASK_ABSOLUTETIME_INFO_COUNT;
    kern_return_t after = acquired == KERN_SUCCESS
        ? task_info(port, TASK_ABSOLUTETIME_INFO, (task_info_t)&info, &count) : acquired;
    printf("{\"task_name_result\":%d,\"live_info_result\":%d,\"reaped_info_result\":%d,\"reaped_cpu_ticks\":%llu}\n",
           acquired, before, after, info.total_user + info.total_system);
    if (port != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), port);
    return 0;
}
