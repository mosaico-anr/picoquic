/*
* Author: Christian Huitema
* Copyright (c) 2017, Private Octopus, Inc.
* All rights reserved.
*
* Permission to use, copy, modify, and distribute this software for any
* purpose with or without fee is hereby granted, provided that the above
* copyright notice and this permission notice appear in all copies.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
* DISCLAIMED. IN NO EVENT SHALL Private Octopus, Inc. BE LIABLE FOR ANY
* DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
* LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
* ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
* SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include "picoquic_internal.h"
#include <stdlib.h>
#include <string.h>

typedef enum {
    picoquic_prague_alg_slow_start = 0,
    picoquic_prague_alg_congestion_avoidance
} picoquic_prague_alg_state_t;

#define PRAGUE_SHIFT_G 4 /* g = 1/2^4, gain parameter for alpha EWMA */
#define PRAGUE_ECT 1
#define PRAGUE_ECN_PLUS_PLUS 0
#define PRAGUE_CA_FALLBACK "cubic"

#define ECN_DEMAND_CWR 1

#define NB_RTT_RENO 4

typedef struct st_picoquic_prague_state_t {
    picoquic_prague_alg_state_t alg_state;
    double alpha;
    uint64_t acked_bytes_ecn;
    uint64_t acked_bytes_total;
    uint32_t ce_state;
    uint64_t loss_cwnd;
    uint64_t last_update_time; 

    uint64_t residual_ack;
    uint64_t ssthresh;
    uint64_t recovery_start;
    uint64_t min_rtt;
    uint64_t last_rtt[NB_RTT_RENO];
    int nb_rtt;

    uint64_t flags;
} picoquic_prague_state_t;


void picoquic_prague_init(picoquic_path_t* path_x)
{
    /* Initialize the state of the congestion control algorithm */
    picoquic_prague_state_t* pr_state = (picoquic_prague_state_t*)malloc(sizeof(picoquic_prague_state_t));

    if (pr_state != NULL) {
        memset(pr_state, 0, sizeof(picoquic_prague_state_t));
        path_x->congestion_alg_state = (void*)pr_state;
        pr_state->alg_state = picoquic_prague_alg_slow_start;
        pr_state->ssthresh = (uint64_t)((int64_t)-1);
        pr_state->alpha = 1;
        path_x->cwin = PICOQUIC_CWIN_INITIAL;
        pr_state->last_update_time = picoquic_current_time();
    }
    else {
        path_x->congestion_alg_state = NULL;
    }
}

/* The recovery state last 1 RTT, during which parameters will be frozen
 */
static void picoquic_newreno_enter_recovery(picoquic_path_t* path_x,
    picoquic_congestion_notification_t notification,
    picoquic_prague_state_t* pr_state,
    uint64_t current_time)
{
    pr_state->ssthresh = path_x->cwin / 2;
    if (pr_state->ssthresh < PICOQUIC_CWIN_MINIMUM) {
        pr_state->ssthresh = PICOQUIC_CWIN_MINIMUM;
    }

    if (notification == picoquic_congestion_notification_timeout) {
        path_x->cwin = PICOQUIC_CWIN_MINIMUM;
        pr_state->alg_state = picoquic_prague_alg_slow_start;
    } else {
        path_x->cwin = pr_state->ssthresh;
        pr_state->alg_state = picoquic_prague_alg_congestion_avoidance;
    }

    pr_state->recovery_start = current_time;

    pr_state->residual_ack = 0;
}


static void picoquic_prague_reset(picoquic_prague_state_t* pr_state)
{
    pr_state->acked_bytes_ecn = 0;
    pr_state->acked_bytes_total = 0;
}

static void picoquic_prague_update_alpha(picoquic_path_t* path_x, picoquic_prague_state_t* pr_state, uint64_t nb_bytes_acknowledged, uint64_t current_time)
{
	/* Expired RTT */
	if (pr_state->last_update_time + path_x->smoothed_rtt <= current_time) {
		/* alpha = (1 - g) * alpha + g * F
		*
		* We use dctcp_shift_g = G = 1 / g
		* and store dctcp_alpha = A = alpha * G
		*
		* The EWMA then becomes A = A * (1 - 1/G) + F
		*
		* We first compute F, the fraction of ecn bytes.
		*/

        /* FIXME correct order of notifications */
        if (pr_state->acked_bytes_total < pr_state->acked_bytes_ecn) {
            pr_state->acked_bytes_total = pr_state->acked_bytes_ecn;
        }
        double F = (double) pr_state->acked_bytes_ecn / (double) pr_state->acked_bytes_total;
        double g = 1.0 / (double) (1 << PRAGUE_SHIFT_G);
        pr_state->alpha = (1.0 - g) * pr_state->alpha + g * F;

        if (pr_state->acked_bytes_ecn > 0) {
            /* If we got ECN marks in the last RTT, update the ssthresh and the CWIN */
            pr_state->loss_cwnd = path_x->cwin;
            //uint64_t reduction = ((uint64_t) ((double) path_x->cwin * pr_state->alpha)) / 2;
            uint64_t reduction = 0;
            pr_state->ssthresh = path_x->cwin - reduction;
            if (pr_state->ssthresh < PICOQUIC_CWIN_MINIMUM) {
                pr_state->ssthresh = PICOQUIC_CWIN_MINIMUM;
            }
            uint64_t old_cwin = path_x->cwin;
            path_x->cwin = pr_state->ssthresh;
            pr_state->alg_state = picoquic_prague_alg_congestion_avoidance;

            fprintf(stdout, "Reducing my cwin, was %lu is now %lu\n", old_cwin, path_x->cwin);
        }

		picoquic_prague_reset(pr_state);
        pr_state->last_update_time = current_time;
	}
}

/*
 * Properly implementing New Reno requires managing a number of
 * signals, such as packet losses or acknowledgements. We attempt
 * to condensate all that in a single API, which could be shared
 * by many different congestion control algorithms.
 */
void picoquic_prague_notify(picoquic_path_t* path_x,
    picoquic_congestion_notification_t notification,
    uint64_t rtt_measurement,
    uint64_t nb_bytes_acknowledged,
    uint64_t lost_packet_number,
    uint64_t current_time)
{
#ifdef _WINDOWS
    UNREFERENCED_PARAMETER(rtt_measurement);
    UNREFERENCED_PARAMETER(lost_packet_number);
#endif
    picoquic_prague_state_t* pr_state = (picoquic_prague_state_t*)path_x->congestion_alg_state;

    if (pr_state != NULL) {
        switch (notification) {
        case picoquic_congestion_notification_acknowledgement: {
            if (nb_bytes_acknowledged) {
                pr_state->acked_bytes_total += nb_bytes_acknowledged;
            }
            // Regardless of the alg state, update alpha
            picoquic_prague_update_alpha(path_x, pr_state, nb_bytes_acknowledged, current_time);
            switch (pr_state->alg_state) {
            case picoquic_prague_alg_slow_start:
                if (path_x->smoothed_rtt <= PICOQUIC_TARGET_RENO_RTT) {
                    path_x->cwin += nb_bytes_acknowledged;
                }
                else {
                    double delta = ((double)path_x->smoothed_rtt) / ((double)PICOQUIC_TARGET_RENO_RTT);
                    delta *= (double)nb_bytes_acknowledged;
                    path_x->cwin += (uint64_t)delta;
                }
                /* if cnx->cwin exceeds SSTHRESH, exit and go to CA */
                if (path_x->cwin >= pr_state->ssthresh) {
                    pr_state->alg_state = picoquic_prague_alg_congestion_avoidance;
                }
                break;
            case picoquic_prague_alg_congestion_avoidance:
            default: {
                uint64_t complete_delta = nb_bytes_acknowledged * path_x->send_mtu + pr_state->residual_ack;
                pr_state->residual_ack = complete_delta % path_x->cwin;
                path_x->cwin += complete_delta / path_x->cwin;
                break;
            }
            }
            break;
        }
        case picoquic_congestion_notification_ecn_ec:
            if (nb_bytes_acknowledged) {
                pr_state->acked_bytes_ecn += nb_bytes_acknowledged;
            }
            picoquic_prague_update_alpha(path_x, pr_state, nb_bytes_acknowledged, current_time);
        case picoquic_congestion_notification_repeat:
        case picoquic_congestion_notification_timeout:
            /* enter recovery */
            if (current_time - pr_state->recovery_start > path_x->smoothed_rtt) {
                picoquic_newreno_enter_recovery(path_x, notification, pr_state, current_time);
            }
            break;
        case picoquic_congestion_notification_spurious_repeat:
            if (current_time - pr_state->recovery_start < path_x->smoothed_rtt) {
                /* If spurious repeat of initial loss detected,
                 * exit recovery and reset threshold to pre-entry cwin.
                 */
                if (path_x->cwin < 2 * pr_state->ssthresh) {
                    path_x->cwin = 2 * pr_state->ssthresh;
                    pr_state->alg_state = picoquic_prague_alg_congestion_avoidance;
                }
            }
            break;
        case picoquic_congestion_notification_rtt_measurement:
            /* Using RTT increases as signal to get out of initial slow start */
            if (pr_state->alg_state == picoquic_prague_alg_slow_start &&
                pr_state->ssthresh == (uint64_t)((int64_t)-1)) {
                uint64_t rolling_min;
                uint64_t delta_rtt;

                if (rtt_measurement < pr_state->min_rtt || pr_state->min_rtt == 0) {
                    pr_state->min_rtt = rtt_measurement;
                }

                if (pr_state->nb_rtt > NB_RTT_RENO) {
                    pr_state->nb_rtt = 0;
                }

                pr_state->last_rtt[pr_state->nb_rtt] = rtt_measurement;
                pr_state->nb_rtt++;

                rolling_min = pr_state->last_rtt[0];

                for (int i = 1; i < NB_RTT_RENO; i++) {
                    if (pr_state->last_rtt[i] == 0) {
                        break;
                    }
                    else if (pr_state->last_rtt[i] < rolling_min) {
                        rolling_min = pr_state->last_rtt[i];
                    }
                }

                delta_rtt = rolling_min - pr_state->min_rtt;
                if (delta_rtt * 4 > pr_state->min_rtt) {
                    /* RTT increased too much, get out of slow start! */
                    pr_state->alg_state = picoquic_prague_alg_congestion_avoidance;
                }
            }
            break;
        default:
            /* ignore */
            break;
        }
    }

    /* Compute pacing data */
    picoquic_update_pacing_data(path_x);
}

/* Release the state of the congestion control algorithm */
void picoquic_prague_delete(picoquic_path_t* path_x)
{
    if (path_x->congestion_alg_state != NULL) {
        free(path_x->congestion_alg_state);
        path_x->congestion_alg_state = NULL;
    }
}

/* Definition record for the QUIC Prague algorithm */

#define picoquic_prague_ID 0x50524147 /* PRAG */

picoquic_congestion_algorithm_t picoquic_prague_algorithm_struct = {
    picoquic_prague_ID,
    picoquic_prague_init,
    picoquic_prague_notify,
    picoquic_prague_delete
};

picoquic_congestion_algorithm_t* picoquic_prague_algorithm = &picoquic_prague_algorithm_struct;
