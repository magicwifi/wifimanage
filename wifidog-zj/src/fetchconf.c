/********************************************************************\
 * This program is free software; you can redistribute it and/or    *
 * modify it under the terms of the GNU General Public License as   *
 * published by the Free Software Foundation; either version 2 of   *
 * the License, or (at your option) any later version.              *
 *                                                                  *
 * This program is distributed in the hope that it will be useful,  *
 * but WITHOUT ANY WARRANTY; without even the implied warranty of   *
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the    *
 * GNU General Public License for more details.                     *
 *                                                                  *
 * You should have received a copy of the GNU General Public License*
 * along with this program; if not, contact:                        *
 *                                                                  *
 * Free Software Foundation           Voice:  +1-617-542-5942       *
 * 59 Temple Place - Suite 330        Fax:    +1-617-542-2652       *
 * Boston, MA  02111-1307,  USA       gnu@gnu.org                   *
 *                                                                  *
 \********************************************************************/

/* $Id: conf.c 1373 2008-09-30 09:27:40Z wichert $ */
/** @file conf.c
  @brief Config file parsing
  @author Copyright (C) 2004 Philippe April <papril777@yahoo.com>
  @author Copyright (C) 2007 Benoit Grégoire, Technologies Coeus inc.
 */

#define _GNU_SOURCE
#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <syslog.h>
#include <signal.h>
#include <errno.h>

#include "../config.h"
#include "safe.h"
#include "common.h"
#include "conf.h"
#include "debug.h"
#include "util.h"
#include "centralserver.h"
#include "firewall.h"
#include "fetchconf.h"



int level = 0;

typedef enum {
	oBadOption,
	oClientTimeout,
	oCheckInterval,
	oAuthInterval,
	oHTTPDMaxConn,
	oTrustedMACList,
	oFirewallRule,
	oAuthServer,
} OpCodes;


static const struct {
	const char *name;
	OpCodes opcode;
} confwords[] = {
	{ "clienttimeout",      	oClientTimeout },
	{ "checkinterval",      	oCheckInterval },
	{ "authinterval",      	oAuthInterval },
	{ "httpdmaxconn",       	oHTTPDMaxConn },
	{ "trustedmaclist",		oTrustedMACList },
	{ "firewallrule",		oFirewallRule },
	{ "authserver",         	oAuthServer },
	{ NULL,				oBadOption },
};

static OpCodes conf_parse_line(const char *line,int paramnum);
static void conf_read(const char *line, s_config	*config);
void parse_trust_mac_list(char *ptr,s_config	*config);
void parse_allow_rules(char *ptr,s_config	*config);
void parse_auth_server();
void fetchconf();


void
thread_fetchconf(void *arg)
{
	pthread_cond_t		cond = PTHREAD_COND_INITIALIZER;
	pthread_mutex_t		cond_mutex = PTHREAD_MUTEX_INITIALIZER;
	struct	timespec	timeout;

	while (1) {
		/* Sleep for config.checkinterval seconds... */
		fetchconf();
		
		timeout.tv_sec = time(NULL) + config_get_config()->checkinterval;
		timeout.tv_nsec = 0;

		/* Mutex must be locked for pthread_cond_timedwait... */
		pthread_mutex_lock(&cond_mutex);

		/* Thread safe "sleep" */
		pthread_cond_timedwait(&cond, &cond_mutex, &timeout);

		/* No longer needs to be locked */
		pthread_mutex_unlock(&cond_mutex);

		debug(LOG_DEBUG, "Running fw_counter()");

		
	}
}


static OpCodes
conf_parse_line(const char *line,int paramnum)
{
	int i;

	for (i = 0; confwords[i].name; i++)
		if (strcasecmp(line, confwords[i].name) == 0)
			return confwords[i].opcode;

	debug(LOG_ERR, "%s: line %d ", line, paramnum);
	
	return oBadOption;
}


#define TO_NEXT_CONF(s, e) do { \
	while (*s != '\0' && *s != '&') { \
		s++; \
	} \
	if (*s != '\0') { \
		*s = '\0'; \
		s++; \
	} else { \
		e = 1; \
	} \
} while (0)

void parse_trust_mac_list(char *ptr,s_config	*config) {
	char *ptrcopy = NULL;
	char *possiblemac = NULL;
	char *mac = NULL;
	char *p1;
	t_trusted_mac *p = NULL;

	debug(LOG_DEBUG, "Parsing string [%s] for trusted MAC addresses", ptr);

	mac = safe_malloc(18);

	/* strsep modifies original, so let's make a copy */
	ptrcopy = safe_strdup(ptr);
	
	if ((p1 = strchr(ptrcopy, '&'))) {
			p1[0] = '\0';
	} 
	

	while ((possiblemac = strsep(&ptrcopy, "+ "))) {
		if (sscanf(possiblemac, " %17[A-Fa-f0-9:]", mac) == 1) {
			/* Copy mac to the list */

			debug(LOG_DEBUG, "Adding MAC address [%s] to trusted list", mac);

			if (config->trustedmaclist == NULL) {
				config->trustedmaclist = safe_malloc(sizeof(t_trusted_mac));
				config->trustedmaclist->mac = safe_strdup(mac);
				config->trustedmaclist->next = NULL;
			}
			else {
				/* Advance to the last entry */
				for (p = config->trustedmaclist; p->next != NULL; p = p->next);
				p->next = safe_malloc(sizeof(t_trusted_mac));
				p = p->next;
				p->mac = safe_strdup(mac);
				p->next = NULL;
			}

		}
	}

	free(ptrcopy);

	free(mac);

}

void parse_allow_rules(char *ptr,s_config	*config) {
	char *ptrcopy = NULL;
	char *possibleip = NULL;
	char *publicip = NULL;
  t_firewall_target target = TARGET_ACCEPT;
	char *p1;
	t_firewall_ruleset *tmpr;
	t_firewall_ruleset *tmpr2;
	t_firewall_rule *tmp;
	t_firewall_rule *tmp2;
	
	debug(LOG_DEBUG, "Parsing string [%s] for trusted IP addresses", ptr);

	publicip = safe_malloc(16);

	/* strsep modifies original, so let's make a copy */
	ptrcopy = safe_strdup(ptr);
		if ((p1 = strchr(ptrcopy, '&'))) {
			p1[0] = '\0';
	} 
	
	
	
	
	while ((possibleip = strsep(&ptrcopy, "+ "))) {
		
		if (sscanf(possibleip, " %15[0-9.]", publicip) == 1) {
			/* Copy mac to the list */
			
			debug(LOG_DEBUG, "Adding IP address [%s] to trusted list", publicip);


		
			tmp = safe_malloc(sizeof(t_firewall_rule));
			memset((void *)tmp, 0, sizeof(t_firewall_rule));
			tmp->target = target;
			tmp->mask = safe_strdup(publicip);
			
				/* Append the rule record */
			if (config->rulesets == NULL) {
				config->rulesets = safe_malloc(sizeof(t_firewall_ruleset));
				memset(config->rulesets, 0, sizeof(t_firewall_ruleset));
				config->rulesets->name = safe_strdup("global");
				tmpr=config->rulesets;
			} else {
				tmpr2 = tmpr = config->rulesets;
				while (tmpr != NULL && (strcmp(tmpr->name, "global") != 0)) {
					tmpr2 = tmpr;
					tmpr = tmpr->next;
				}
				if (tmpr == NULL) {
					/* Rule did not exist */
					tmpr = safe_malloc(sizeof(t_firewall_ruleset));
					memset(tmpr, 0, sizeof(t_firewall_ruleset));
					tmpr->name = safe_strdup("global");
					tmpr2->next = tmpr;
				}
			}
		
			/* At this point, tmpr == current ruleset */
			if (tmpr->rules == NULL) {
				/* No rules... */
				tmpr->rules = tmp;
			} else {
				tmp2 = tmpr->rules;
				while (tmp2->next != NULL)
					tmp2 = tmp2->next;
				tmp2->next = tmp;
			}

		}
	}

	free(ptrcopy);

	free(publicip);

}



void
conf_read(const char *line,s_config	*config)
{
	char *s, *p1;
	int opcode, value,finished=0,paramnum=0;
	
	int linenum = strlen(line);
	
	if(linenum == 0){
		return;
	}
	
	debug(LOG_DEBUG, "linenum:%d",linenum);
	s = line;

	while (finished==0) {
		paramnum++;
		debug(LOG_DEBUG, "begin parse %d",paramnum);
		
		if (s[strlen(s) - 1] == '\n')
			s[strlen(s) - 1] = '\0';

		if ((p1 = strchr(s, '='))) {
			p1[0] = '\0';
		} 
		
		if (p1) {
			p1++;
		}

		if (p1 && p1[0] != '\0') {

			opcode = conf_parse_line(s,paramnum);

			switch(opcode) {
			case oHTTPDMaxConn:
				sscanf(p1, "%d", &(config->httpdmaxconn));
				debug(LOG_DEBUG, "HTTPDMaxConn");
				break;
			case oCheckInterval:
				sscanf(p1, "%d", &(config->checkinterval));
				debug(LOG_DEBUG, "oCheckInterval");
				break;
			case oAuthInterval:
				sscanf(p1, "%d", &(config->authinterval));
				debug(LOG_DEBUG, "oAuthInterval");
				break;
			case oClientTimeout:
				sscanf(p1, "%d", &(config->clienttimeout));
				debug(LOG_DEBUG, "oClientTimeout");
				break;
			case oTrustedMACList:
				parse_trust_mac_list(p1,config);
				break;
			case oFirewallRule:
				parse_allow_rules(p1,config);
				break;
			case oAuthServer:
				parse_auth_server(p1,config);
				break;
			case oBadOption:
				debug(LOG_DEBUG, "oBadOption");
				break;

			}
			debug(LOG_DEBUG, "this word %s %d",s,finished);
			s = p1;
			TO_NEXT_CONF(s, finished);
			debug(LOG_DEBUG, "next word %s %d",s,finished);
			
		}
	}

}

void
parse_auth_server(char *ptr,s_config	*config)
{
	char		*host = ptr,
			*path = NULL,
			*loginscriptpathfragment = NULL,
			*portalscriptpathfragment = NULL,
			*msgscriptpathfragment = NULL,
			*pingscriptpathfragment = NULL,
			*authscriptpathfragment = NULL;
	int		http_port,
			ssl_port,
			ssl_available;
			
	t_serv	*new,
			*tmp;
	
		/* only proceed if we have an host and a path */
	if (host == NULL)
		return;
	
	
	/* Defaults */
	path = safe_strdup(DEFAULT_AUTHSERVPATH);
	loginscriptpathfragment = safe_strdup(DEFAULT_AUTHSERVLOGINPATHFRAGMENT);
	portalscriptpathfragment = safe_strdup(DEFAULT_AUTHSERVPORTALPATHFRAGMENT);
	msgscriptpathfragment = safe_strdup(DEFAULT_AUTHSERVMSGPATHFRAGMENT);
	pingscriptpathfragment = safe_strdup(DEFAULT_AUTHSERVPINGPATHFRAGMENT);
	authscriptpathfragment = safe_strdup(DEFAULT_AUTHSERVAUTHPATHFRAGMENT);
	http_port = DEFAULT_AUTHSERVPORT;
	ssl_port = DEFAULT_AUTHSERVSSLPORT;
	ssl_available = DEFAULT_AUTHSERVSSLAVAILABLE;



	/* Allocate memory */
	new = safe_malloc(sizeof(t_serv));

	/* Fill in struct */
	memset(new, 0, sizeof(t_serv)); /*< Fill all with NULL */
	new->serv_hostname = safe_strdup(host);
	new->serv_use_ssl = ssl_available;
	new->serv_path = path;
	new->serv_login_script_path_fragment = loginscriptpathfragment;
	new->serv_portal_script_path_fragment = portalscriptpathfragment;
	new->serv_msg_script_path_fragment = msgscriptpathfragment;    
	new->serv_ping_script_path_fragment = pingscriptpathfragment;  
	new->serv_auth_script_path_fragment = authscriptpathfragment;  
	new->serv_http_port = http_port;
	new->serv_ssl_port = ssl_port;

	t_serv	*auth_servers = NULL;
	auth_servers = config->auth_servers;
	
	for (tmp = auth_servers; tmp->next != NULL;tmp = tmp->next);
	tmp->next = new;
	mark_auth_server_bad(auth_servers);
	/*
	mark_auth_server_bad(auth_servers);
	*/
	debug(LOG_DEBUG, "Auth server added from Platform");
	
	
}




void
fetchconf()
{
        ssize_t			numbytes;
        size_t	        	totalbytes;
	int		sockfd, nfds, done;

	char			request[MAX_BUF];
	fd_set			readfds;
	struct timeval		timeout;
	FILE * fh;
	
	char  *str = NULL;
	int interval;
	t_serv	*auth_server = NULL;
	auth_server = get_auth_server();
	
	
	sockfd = connect_server(1);
	if (sockfd == -1||level ==1) {
	
		return;
		
	}
	s_config *config=config_get_config();
	/*
	 * Prep & send request
	 */
	snprintf(request, sizeof(request) - 1,
			"GET %sfetchconf/?gw_id=%s HTTP/1.0\r\n"
			"User-Agent: WiFiDog %s\r\n"
			"Host: %s\r\n"
			"\r\n",
			auth_server->serv_path,
			config->gw_id,
			VERSION,
			auth_server->serv_hostname);

	
	send(sockfd, request, strlen(request), 0);

	debug(LOG_DEBUG, "Reading response %s %s",auth_server->serv_path,auth_server->serv_hostname);
	
	numbytes = totalbytes = 0;
	done = 0;
	do {
		FD_ZERO(&readfds);
		FD_SET(sockfd, &readfds);
		timeout.tv_sec = 30; /* XXX magic... 30 second */
		timeout.tv_usec = 0;
		nfds = sockfd + 1;

		nfds = select(nfds, &readfds, NULL, NULL, &timeout);

		if (nfds > 0) {
			/** We don't have to use FD_ISSET() because there
			 *  was only one fd. */
			numbytes = read(sockfd, request + totalbytes, MAX_BUF - (totalbytes + 1));
			if (numbytes < 0) {
				debug(LOG_ERR, "An error occurred while reading from auth server: %s", strerror(errno));
				/* FIXME */
				close(sockfd);
				return;
			}
			else if (numbytes == 0) {
				done = 1;
			}
			else {
				totalbytes += numbytes;
				debug(LOG_DEBUG, "Read %d bytes, total now %d", numbytes, totalbytes);
			}
		}
		else if (nfds == 0) {
			debug(LOG_ERR, "Timed out reading data via select() from auth server");
			/* FIXME */
			close(sockfd);
			return;
		}
		else if (nfds < 0) {
			debug(LOG_ERR, "Error reading data via select() from auth server: %s", strerror(errno));
			/* FIXME */
			close(sockfd);
			return;
		}
	} while (!done);
	close(sockfd);

	debug(LOG_DEBUG, "Done reading reply, total %d bytes", totalbytes);

	request[totalbytes] = '\0';
	
	
	
	
	debug(LOG_DEBUG, "HTTP Response from Server: [%s]", request);
	
   	str = strstr(request, "Conf:");
		if(str){	
			str =str+5;
			debug(LOG_DEBUG, "config %s", str);
			conf_read(str,config);
			level = 1;
			fw_destroy();
			if (!fw_init()) {
				debug(LOG_ERR, "FATAL: Failed to initialize firewall");
				exit(1);
			}
			debug(LOG_DEBUG, "Auth Server Says OK" );	
		}					
	

	
	return;	
}

