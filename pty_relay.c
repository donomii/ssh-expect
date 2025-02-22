#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <pthread.h>

int master_fd;

void *read_from_master(void *arg) {
    char buffer[4096];
    ssize_t bytes_read;

    fprintf(stderr, "read_from_master thread started\n");

    while ((bytes_read = read(master_fd, buffer, sizeof(buffer))) > 0) {
        fprintf(stderr, "read_from_master: read %zd bytes from master\n", bytes_read);
        write(STDOUT_FILENO, buffer, bytes_read);
    }

    if (bytes_read == -1) {
        perror("read from master");
    }
    fprintf(stderr, "read_from_master thread exiting\n");
    return NULL;
}

void *write_to_master(void *arg) {
    char buffer[4096];
    ssize_t bytes_read;

    fprintf(stderr, "write_to_master thread started\n");

    while ((bytes_read = read(STDIN_FILENO, buffer, sizeof(buffer))) > 0) {
        fprintf(stderr, "write_to_master: read %zd bytes from stdin\n", bytes_read);
        write(master_fd, buffer, bytes_read);
    }

    if (bytes_read == -1) {
        perror("read from stdin");
    }
    fprintf(stderr, "write_to_master thread exiting\n");
    return NULL;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        return 1;
    }

    char *slave_name;
    pid_t pid;
    pthread_t read_thread, write_thread;

    fprintf(stderr, "Starting pty_relay\n");

    master_fd = posix_openpt(O_RDWR | O_NOCTTY);
    fprintf(stderr, "posix_openpt: master_fd = %d\n", master_fd);
    if (master_fd == -1) {
        perror("posix_openpt");
        return 1;
    }

    if (grantpt(master_fd) == -1) {
        perror("grantpt");
        close(master_fd);
        return 1;
    }

    if (unlockpt(master_fd) == -1) {
        perror("unlockpt");
        close(master_fd);
        return 1;
    }

    slave_name = ptsname(master_fd);
    fprintf(stderr, "ptsname: slave_name = %s\n", slave_name);
    if (slave_name == NULL) {
        perror("ptsname");
        close(master_fd);
        return 1;
    }

    pid = fork();
    fprintf(stderr, "fork: pid = %d\n", pid);
    if (pid == -1) {
        perror("fork");
        close(master_fd);
        return 1;
    }

    if (pid == 0) { // Child process
        int slave_fd;
        struct termios term_settings;

        setsid();
        fprintf(stderr, "Child process: setsid called\n");

        slave_fd = open(slave_name, O_RDWR);
        fprintf(stderr, "Child process: open slave_fd = %d\n", slave_fd);
        if (slave_fd == -1) {
            perror("open slave");
            exit(1);
        }

        dup2(slave_fd, STDIN_FILENO);
        dup2(slave_fd, STDOUT_FILENO);
        dup2(slave_fd, STDERR_FILENO);
        fprintf(stderr, "Child process: dup2 called\n");
        close(slave_fd);
        close(master_fd);

        tcgetattr(STDIN_FILENO, &term_settings);
        cfmakeraw(&term_settings);
        tcsetattr(STDIN_FILENO, TCSANOW, &term_settings);
        fprintf(stderr, "Child process: termios settings applied\n");

        fprintf(stderr, "Child process: Attempting to execute: %s\n", argv[1]);

        execvp(argv[1], argv);
        perror("execvp");
        exit(1);
    } else { // Parent process
        pthread_create(&read_thread, NULL, read_from_master, NULL);
        pthread_create(&write_thread, NULL, write_to_master, NULL);

        fprintf(stderr, "Parent process: threads created\n");

        pthread_join(read_thread, NULL);
        pthread_join(write_thread, NULL);

        fprintf(stderr, "Parent process: threads joined\n");

        int status;
        waitpid(pid, &status, 0);
        fprintf(stderr, "Parent process: waitpid returned status = %d\n", status);
        close(master_fd);
        return WEXITSTATUS(status);
    }
}
