/*
 * Please do not edit this file.
 * It was generated using rpcgen.
 */

#include "rpcace.h"
#include <stdio.h>
#include <stdlib.h>
#include <rpc/pmap_clnt.h>
#include <string.h>
#include <sys/ioctl.h> /* ioctl, TIOCNOTTY */
#include <sys/types.h> /* open */
#include <sys/stat.h> /* open */
#include <fcntl.h> /* open */
#include <unistd.h> /* getdtablesize */
#include <memory.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <syslog.h>

#ifndef SIG_PF
#define SIG_PF void(*)(int)
#endif
 int _rpcpmstart;		/* Started by a port monitor ? */
 int _rpcfdtype;		/* Whether Stream or Datagram ? */

static
void _msgout (char* msg)
{
#ifdef RPC_SVC_FG
	if (_rpcpmstart)
		syslog (LOG_ERR, "%s", msg);
	else
		fprintf (stderr, "%s\n", msg);
#else
	syslog (LOG_ERR, "%s", msg);
#endif
}

static void
rpc_ace_1(struct svc_req *rqstp, register SVCXPRT *transp)
{
	union {
		ace_data ace_server_1_arg;
	} argument;
	char *result;
	xdrproc_t _xdr_argument, _xdr_result;
	char *(*local)(char *, struct svc_req *);

	switch (rqstp->rq_proc) {
	case NULLPROC:
		(void) svc_sendreply (transp, (xdrproc_t) xdr_void, (char *)NULL);
		return;

	case ACE_SERVER:
		_xdr_argument = (xdrproc_t) xdr_ace_data;
		_xdr_result = (xdrproc_t) xdr_ace_reponse;
		local = (char *(*)(char *, struct svc_req *)) ace_server_1_svc;
		break;

	default:
		svcerr_noproc (transp);
		return;
	}
	memset ((char *)&argument, 0, sizeof (argument));
	if (!svc_getargs (transp, (xdrproc_t) _xdr_argument, (caddr_t) &argument)) {
		svcerr_decode (transp);
		return;
	}
	result = (*local)((char *)&argument, rqstp);
	if (result != NULL && !svc_sendreply(transp, (xdrproc_t) _xdr_result, result)) {
		svcerr_systemerr (transp);
	}
	if (!svc_freeargs (transp, (xdrproc_t) _xdr_argument, (caddr_t) &argument)) {
		_msgout ("unable to free arguments");
		exit (1);
	}
	return;
}

int
main (int argc, char **argv)
{
	register SVCXPRT *transp;
	int sock;
	int proto;
	struct sockaddr_in saddr;
	int asize = sizeof (saddr);

	if (getsockname (0, (struct sockaddr *)&saddr, &asize) == 0) {
		int ssize = sizeof (int);

		if (saddr.sin_family != AF_INET)
			exit (1);
		if (getsockopt (0, SOL_SOCKET, SO_TYPE,
				(char *)&_rpcfdtype, &ssize) == -1)
			exit (1);
		sock = 0;
		_rpcpmstart = 1;
		proto = 0;
		openlog("rpcace", LOG_PID, LOG_DAEMON);
	} else {
#ifndef RPC_SVC_FG
		int size;
		int pid, i;

		pid = fork();
		if (pid < 0) {
			perror("cannot fork");
			exit(1);
		}
		if (pid)
			exit(0);
		size = getdtablesize();
		for (i = 0; i < size; i++)
			(void) close(i);
		i = open("/dev/console", 2);
		(void) dup2(i, 1);
		(void) dup2(i, 2);
		i = open("/dev/tty", 2);
		if (i >= 0) {
			(void) ioctl(i, TIOCNOTTY, (char *)NULL);
			(void) close(i);
		}
		openlog("rpcace", LOG_PID, LOG_DAEMON);
#endif
		sock = RPC_ANYSOCK;
		pmap_unset (RPC_ACE, RPC_ACE_VERS);
	}

	if ((_rpcfdtype == 0) || (_rpcfdtype == SOCK_DGRAM)) {
		transp = svcudp_create(sock);
		if (transp == NULL) {
			_msgout ("cannot create udp service.");
			exit(1);
		}
		if (!_rpcpmstart)
			proto = IPPROTO_UDP;
		if (!svc_register(transp, RPC_ACE, RPC_ACE_VERS, rpc_ace_1, proto)) {
			_msgout ("unable to register (RPC_ACE, RPC_ACE_VERS, udp).");
			exit(1);
		}
	}

	if ((_rpcfdtype == 0) || (_rpcfdtype == SOCK_STREAM)) {
		transp = svctcp_create(sock, 0, 0);
		if (transp == NULL) {
			_msgout ("cannot create tcp service.");
			exit(1);
		}
		if (!_rpcpmstart)
			proto = IPPROTO_TCP;
		if (!svc_register(transp, RPC_ACE, RPC_ACE_VERS, rpc_ace_1, proto)) {
			_msgout ("unable to register (RPC_ACE, RPC_ACE_VERS, tcp).");
			exit(1);
		}
	}

	if (transp == (SVCXPRT *)NULL) {
		_msgout ("could not create a handle");
		exit (1);
	}
	svc_run ();
	_msgout ("svc_run returned");
	exit (1);
	/* NOTREACHED */
}
