package transcode

import (
	"context"
	"errors"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// maxSubtitleJobsPerUser is one track on the worker and one behind it. More than that is
// ErrBusy, without a place in the queue: nobody needs three tracks of one film prepared at
// once, and one user asking for all of them must not fill the queue in front of the rest.
const maxSubtitleJobsPerUser = 2

// subtitleWork is the state of the one worker, guarded by Manager.mu.
type subtitleWork struct {
	// jobs holds every track that is queued or running, by key: a second request joins.
	jobs     map[string]*subtitleJob
	queue    []*subtitleJob
	running  *subtitleJob
	lastUser id.ID
}

// subtitleJob is one track. It lives as long as somebody wants the result: requests that
// wait for it, and for SubtitleGrace after the last of them left.
type subtitleJob struct {
	key, target, dir, fingerprint string
	limit                         int64
	params                        SubtitleParams

	waiters int
	// idle numbers the moments nobody waited; an older grace period no longer counts.
	idle   int
	cancel context.CancelFunc

	done chan struct{}
	err  error
}

// joinSubtitleJob adds a request to its track, or queues the track for this user.
func (m *Manager) joinSubtitleJob(job *subtitleJob) (*subtitleJob, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.closed {
		return nil, ErrStopped
	}
	if current, ok := m.subtitles.jobs[job.key]; ok {
		current.waiters++
		current.idle++
		return current, nil
	}
	share := 0
	for _, other := range m.subtitles.jobs {
		if other.params.User == job.params.User {
			share++
		}
	}
	if share >= maxSubtitleJobsPerUser {
		return nil, ErrBusy
	}
	job.waiters = 1
	m.subtitles.jobs[job.key] = job
	m.subtitles.queue = append(m.subtitles.queue, job)
	m.startSubtitleJob()
	return job, nil
}

// leaveSubtitleJob ends one request's interest. An answered poll and an aborted request are
// the same here: the repeat comes after Retry-After, or a proxy cut a silent request off, and
// neither should restart a film-long read. So the job gets SubtitleGrace, and without a repeat
// it stops. That is what keeps a user who left from holding the worker for ten minutes.
func (m *Manager) leaveSubtitleJob(job *subtitleJob) {
	m.mu.Lock()
	defer m.mu.Unlock()
	job.waiters--
	if job.waiters > 0 || m.subtitles.jobs[job.key] != job {
		return
	}
	job.idle++
	idle := job.idle
	time.AfterFunc(m.o.SubtitleGrace, func() { m.abandonSubtitleJob(job, idle) })
}

func (m *Manager) abandonSubtitleJob(job *subtitleJob, idle int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if job.idle != idle || job.waiters > 0 || m.subtitles.jobs[job.key] != job {
		return
	}
	delete(m.subtitles.jobs, job.key)
	if job.cancel != nil {
		job.cancel() // runSubtitleJob clears the worker once ffmpeg is gone
		return
	}
	for i, queued := range m.subtitles.queue {
		if queued == job {
			m.subtitles.queue = append(m.subtitles.queue[:i], m.subtitles.queue[i+1:]...)
			break
		}
	}
}

// startSubtitleJob gives a free worker to the oldest job of somebody else than the previous
// user, and to the same user only when nobody else waits. The caller holds m.mu.
func (m *Manager) startSubtitleJob() {
	work := &m.subtitles
	if work.running != nil || len(work.queue) == 0 || m.closed {
		return
	}
	next := 0
	for i, job := range work.queue {
		if job.params.User != work.lastUser {
			next = i
			break
		}
	}
	job := work.queue[next]
	work.queue = append(work.queue[:next], work.queue[next+1:]...)
	ctx, cancel := context.WithCancel(context.Background())
	job.cancel = cancel
	work.running, work.lastUser = job, job.params.User
	m.wg.Add(1)
	go m.runSubtitleJob(ctx, job)
}

func (m *Manager) runSubtitleJob(ctx context.Context, job *subtitleJob) {
	defer m.wg.Done()
	defer job.cancel()
	err := m.extractSubtitleFile(ctx, job.params, job.fingerprint, job.dir, job.target, job.limit)
	switch {
	case err == nil:
		m.trimSubtitleCache(job.dir)
	case errors.Is(err, ErrFailed):
		m.rememberSubtitleFailure(job.key)
	}
	m.mu.Lock()
	job.err = err
	if m.subtitles.jobs[job.key] == job {
		delete(m.subtitles.jobs, job.key)
	}
	m.subtitles.running = nil
	m.startSubtitleJob()
	m.mu.Unlock()
	close(job.done)
}

// dropQueuedSubtitles answers everything behind the worker when the manager closes. The
// running job stops on m.stop.
func (m *Manager) dropQueuedSubtitles() {
	m.mu.Lock()
	queued := m.subtitles.queue
	m.subtitles.queue = nil
	for _, job := range queued {
		delete(m.subtitles.jobs, job.key)
	}
	m.mu.Unlock()
	for _, job := range queued {
		job.err = ErrStopped
		close(job.done)
	}
}
