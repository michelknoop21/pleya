package backup

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
)

// CreateArgs en VerifyArgs zijn de argumenten van de twee jobs.
type CreateArgs struct {
	BackupID string `json:"backup_id"`
}

type VerifyArgs struct {
	TestID string `json:"test_id"`
}

// CreateHandler voert backup_create uit. Is de back-up gepland en geslaagd en
// was er deze week nog geen geslaagde hersteltest, dan zet hij er een achteraan
// (RB-26: de hersteltest is wekelijks).
func CreateHandler(s *Service, runner *jobs.Runner) jobs.Handler {
	return func(ctx context.Context, job jobs.Job) error {
		var args CreateArgs
		if err := json.Unmarshal(job.Args, &args); err != nil {
			return fmt.Errorf("argumenten van %s: %w", JobCreate, err)
		}
		backupID, err := id.Parse(args.BackupID)
		if err != nil {
			return err
		}
		if err := s.Run(ctx, backupID); err != nil {
			return err
		}
		rec, err := s.Get(ctx, backupID)
		if err != nil || rec.Status != StatusOK || rec.Trigger != TriggerSchedule || runner == nil {
			return nil
		}
		if due, err := s.VerifyDue(ctx); err != nil || !due {
			return nil
		}
		return s.EnqueueVerify(ctx, runner, backupID)
	}
}

// EnqueueVerify legt een hersteltest vast en zet hem in de wachtrij. Staat er
// al een, dan gebeurt er niets en geeft hij ErrBusy.
func (s *Service) EnqueueVerify(ctx context.Context, runner *jobs.Runner, backupID id.ID) error {
	_, err := s.StartVerify(ctx, runner, backupID)
	return err
}

// StartVerify is EnqueueVerify met de id van de nieuwe test erbij, voor de API.
func (s *Service) StartVerify(ctx context.Context, runner *jobs.Runner, backupID id.ID) (id.ID, error) {
	testID, err := s.BeginVerify(ctx, backupID)
	if err != nil {
		return id.Nil, err
	}
	_, queued, err := runner.Enqueue(ctx, JobVerify, VerifyArgs{TestID: testID.String()}, "backup-verify", s.now())
	if err == nil && !queued {
		err = ErrBusy
	}
	if err != nil {
		_ = s.DiscardVerify(context.WithoutCancel(ctx), testID)
		return id.Nil, err
	}
	return testID, nil
}

// Start legt een back-up vast en zet hem in de wachtrij. Eén tegelijk: de
// dedupe-sleutel houdt een tweede aanvraag tegen zolang de eerste wacht of
// loopt, en dan is het ErrBusy.
func (s *Service) Start(ctx context.Context, runner *jobs.Runner, trigger Trigger) (id.ID, error) {
	backupID, err := s.Begin(ctx, trigger)
	if err != nil {
		return id.Nil, err
	}
	_, queued, err := runner.Enqueue(ctx, JobCreate, CreateArgs{BackupID: backupID.String()}, "backup", s.now())
	if err == nil && !queued {
		err = ErrBusy
	}
	if err != nil {
		_ = s.Discard(context.WithoutCancel(ctx), backupID)
		return id.Nil, err
	}
	return backupID, nil
}

// VerifyHandler voert backup_verify uit.
func VerifyHandler(s *Service) jobs.Handler {
	return func(ctx context.Context, job jobs.Job) error {
		var args VerifyArgs
		if err := json.Unmarshal(job.Args, &args); err != nil {
			return fmt.Errorf("argumenten van %s: %w", JobVerify, err)
		}
		testID, err := id.Parse(args.TestID)
		if err != nil {
			return err
		}
		return s.RunVerify(ctx, testID)
	}
}
