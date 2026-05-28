//-------------------------------------------------------------------------------------------------
// send_cli.c 
// send all command line arguments to a TCP port
//
// Build on Windows: gcc send-cli.c -o send-cli.exe -lws2_32
//             MSVC: cl send-cli.c ws2_32.lib
// Build on Linux  : gcc send-cli.c -o send-cli
//
//
// https://github.com/htminuslab            
//
//-------------------------------------------------------------------------------------------------
// Version   Author          Date          Changes
// 0.1       Hans Tiggeler   23 May 2026 
//------------------------------------------------------------------------------------------------
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #ifdef _MSC_VER
    #pragma comment(lib, "ws2_32.lib")
  #endif
  typedef SOCKET sock_t;
  #define CLOSESOCK(s) closesocket(s)
  #define SOCK_INVALID INVALID_SOCKET
  #define SOCK_ERR     SOCKET_ERROR
#else
  #include <sys/types.h>
  #include <sys/socket.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #include <unistd.h>
  #include <errno.h>
  typedef int sock_t;
  #define CLOSESOCK(s) close(s)
  #define SOCK_INVALID (-1)
  #define SOCK_ERR     (-1)
#endif

#define SERVER_ADDR "127.0.0.1"
#define BUFFER_SIZE 4096

static int net_init(void)
{
#ifdef _WIN32
    WSADATA wsaData;
    int rc = WSAStartup(MAKEWORD(2, 2), &wsaData);
    if (rc != 0) {
        fprintf(stderr, "WSAStartup failed: %d\n", rc);
        return -1;
    }
#endif
    return 0;
}

static void net_cleanup(void)
{
#ifdef _WIN32
    WSACleanup();
#endif
}

int main(int argc, char *argv[])
{
    sock_t sock = SOCK_INVALID;
    struct sockaddr_in server;
    char *port_env;
    int port;
    char buffer[BUFFER_SIZE];
    int i;
    int result;

    /* Check command line arguments */
    if (argc < 2)
    {
        fprintf(stderr, "Usage: %s <message>\n", argv[0]);
        return 1;
    }

    /* Read port from environment variable */
    port_env = getenv("TCL_CLI_PORT");

    if (port_env == NULL)
    {
        fprintf(stderr, "Error: TCL_CLI_PORT environment variable not set.\n");
        return 1;
    }

    port = atoi(port_env);

    if (port <= 0 || port > 65535)
    {
        fprintf(stderr, "Error: Invalid port number in TCL_CLI_PORT.\n");
        return 1;
    }

    /* Build message string, leaving 3 bytes free for trailing "\r\n\0" */
    buffer[0] = '\0';

    for (i = 1; i < argc; i++)
    {
        if ((strlen(buffer) + strlen(argv[i]) + 4) >= BUFFER_SIZE)
        {
            fprintf(stderr, "Error: Command line too long.\n");
            return 1;
        }

        strcat(buffer, argv[i]);

        if (i != (argc - 1))
        {
            strcat(buffer, " ");
        }
    }

    /* Terminate with CRLF so the server's line-buffered gets returns */
    strcat(buffer, "\r\n");

    /* Initialize networking (Winsock on Windows, no-op elsewhere) */
    if (net_init() != 0)
    {
        return 1;
    }

    /* Create socket */
    sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);

    if (sock == SOCK_INVALID)
    {
        fprintf(stderr, "Socket creation failed.\n");
        net_cleanup();
        return 1;
    }

    /* Configure server address */
    memset(&server, 0, sizeof(server));
    server.sin_family = AF_INET;
    server.sin_port = htons((unsigned short)port);

    if (inet_pton(AF_INET, SERVER_ADDR, &server.sin_addr) <= 0)
    {
        fprintf(stderr, "Invalid server address.\n");
        CLOSESOCK(sock);
        net_cleanup();
        return 1;
    }

    /* Connect to server */
    if (connect(sock, (struct sockaddr *)&server, sizeof(server)) == SOCK_ERR)
    {
        fprintf(stderr,
                "Error: Cannot connect to %s:%d (port not open or server not responding).\n",
                SERVER_ADDR,
                port);

        CLOSESOCK(sock);
        net_cleanup();
        return 1;
    }

    /* Send data */
    result = send(sock, buffer, (int)strlen(buffer), 0);

    if (result == SOCK_ERR)
    {
        fprintf(stderr, "Send failed.\n");
        CLOSESOCK(sock);
        net_cleanup();
        return 1;
    }

    /* Read response from server until the peer closes or buffer fills.
     * The server writes one line of JSON then closes the channel. */
    {
        char reply[BUFFER_SIZE];
        int  total = 0;
        int  n;

        for (;;)
        {
            n = recv(sock, reply + total, (int)(sizeof(reply) - 1 - total), 0);

            if (n == 0)              /* peer closed */
            {
                break;
            }
            if (n == SOCK_ERR)
            {
                fprintf(stderr, "Recv failed.\n");
                CLOSESOCK(sock);
                net_cleanup();
                return 1;
            }

            total += n;

            if (total >= (int)(sizeof(reply) - 1))
            {
                break;               /* buffer full */
            }
        }

        reply[total] = '\0';

        /* Strip a trailing CR/LF pair so callers (PowerShell ConvertFrom-Json,
         * jq, etc.) see a clean single-line JSON object. */
        while (total > 0 && (reply[total - 1] == '\n' || reply[total - 1] == '\r'))
        {
            reply[--total] = '\0';
        }

        if (total > 0)
        {
            printf("%s\n", reply);
        }
    }

    /* Cleanup */
    CLOSESOCK(sock);
    net_cleanup();

    return 0;
}
