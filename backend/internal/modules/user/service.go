package user

import (
	"context"
	"regexp"
	"slices"
	"strings"
	"time"

	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/pagination"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/pkg/security"
	"skills-analyzer/internal/rbac"
)

type CreateRequest struct {
	ReferenceNumber *string `json:"reference_number" binding:"omitempty,max=50"`
	Name            string  `json:"name" binding:"required,max=150"`
	Mobile          *string `json:"mobile"`
	Email           *string `json:"email" binding:"omitempty,email"`
	Username        string  `json:"username" binding:"required,min=3,max=60"`
	// Optional: a user without a password can still sign in by OTP or use "forgot password".
	Password     *string `json:"password" binding:"omitempty,min=8,max=72"`
	DepartmentID *int64  `json:"department_id"`
	Gender       *string `json:"gender" binding:"omitempty,oneof=male female other"`
	DOB          *string `json:"dob"` // YYYY-MM-DD
	RoleIDs      []int64 `json:"role_ids" binding:"required,min=1"`
}

type UpdateRequest struct {
	ReferenceNumber *string `json:"reference_number" binding:"omitempty,max=50"`
	Name            string  `json:"name" binding:"required,max=150"`
	Mobile          *string `json:"mobile"`
	Email           *string `json:"email" binding:"omitempty,email"`
	Username        string  `json:"username" binding:"required,min=3,max=60"`
	DepartmentID    *int64  `json:"department_id"`
	Gender          *string `json:"gender" binding:"omitempty,oneof=male female other"`
	DOB             *string `json:"dob"`
}

type SetRolesRequest struct {
	RoleIDs []int64 `json:"role_ids" binding:"required,min=1"`
}

type SetStatusRequest struct {
	IsActive *bool `json:"is_active" binding:"required"`
}

type SetPasswordRequest struct {
	Password string `json:"password" binding:"required,min=8,max=72"`
}

// Actor is the logged-in user performing the change.
type Actor struct {
	ID    int64
	Roles []string
}

func (a Actor) isAdmin() bool { return slices.Contains(a.Roles, rbac.AdminRole) }

type Service struct{ repo *Repository }

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

var (
	mobileRe   = regexp.MustCompile(`^[6-9]\d{9}$`) // Indian 10-digit mobile
	usernameRe = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)
)

func (s *Service) List(ctx context.Context, f Filter, p pagination.Params) ([]*User, int64, error) {
	return s.repo.List(ctx, f, p)
}

func (s *Service) Get(ctx context.Context, id int64) (*User, error) {
	u, err := s.repo.Get(ctx, id)
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("User not found")
	}
	return u, err
}

func (s *Service) Create(ctx context.Context, req CreateRequest, actor Actor) (*User, error) {
	f, err := s.normalize(ctx, req.ReferenceNumber, req.Name, req.Mobile, req.Email, req.Username, req.DepartmentID, req.Gender, req.DOB)
	if err != nil {
		return nil, err
	}
	if err := s.validateRoles(ctx, req.RoleIDs, actor); err != nil {
		return nil, err
	}
	var hash *string
	if req.Password != nil && *req.Password != "" {
		h, err := security.HashPassword(*req.Password)
		if err != nil {
			return nil, err
		}
		hash = &h
	}
	id, err := s.repo.Create(ctx, *f, hash, req.RoleIDs, actor.ID)
	if err != nil {
		return nil, mapWriteErr(err)
	}
	return s.repo.Get(ctx, id)
}

func (s *Service) Update(ctx context.Context, id int64, req UpdateRequest, actor Actor) (*User, error) {
	if _, err := s.Get(ctx, id); err != nil {
		return nil, err
	}
	f, err := s.normalize(ctx, req.ReferenceNumber, req.Name, req.Mobile, req.Email, req.Username, req.DepartmentID, req.Gender, req.DOB)
	if err != nil {
		return nil, err
	}
	if err := s.repo.Update(ctx, id, *f, actor.ID); err != nil {
		return nil, mapWriteErr(err)
	}
	return s.repo.Get(ctx, id)
}

func (s *Service) SetStatus(ctx context.Context, id int64, active bool, actor Actor) (*User, error) {
	if id == actor.ID && !active {
		return nil, response.Conflict("You cannot deactivate your own account")
	}
	u, err := s.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	if hasRole(u, rbac.AdminRole) && !actor.isAdmin() {
		return nil, response.Forbidden("Only an admin can change another admin's status")
	}
	if err := s.repo.SetActive(ctx, id, active, actor.ID); err != nil {
		return nil, mapWriteErr(err) // reactivating can collide with a newer user holding the same username
	}
	return s.repo.Get(ctx, id)
}

func (s *Service) SetRoles(ctx context.Context, id int64, roleIDs []int64, actor Actor) (*User, error) {
	u, err := s.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	if err := s.validateRoles(ctx, roleIDs, actor); err != nil {
		return nil, err
	}
	if hasRole(u, rbac.AdminRole) && !actor.isAdmin() {
		return nil, response.Forbidden("Only an admin can change another admin's roles")
	}
	if id == actor.ID && actor.isAdmin() {
		keepsAdmin := false
		for _, r := range u.Roles {
			if r.Slug == rbac.AdminRole && slices.Contains(roleIDs, r.ID) {
				keepsAdmin = true
			}
		}
		if !keepsAdmin {
			return nil, response.Conflict("You cannot remove the admin role from yourself")
		}
	}
	if err := s.repo.SetRoles(ctx, id, roleIDs, actor.ID); err != nil {
		return nil, err
	}
	return s.repo.Get(ctx, id)
}

func (s *Service) SetPassword(ctx context.Context, id int64, password string, actor Actor) error {
	u, err := s.Get(ctx, id)
	if err != nil {
		return err
	}
	if hasRole(u, rbac.AdminRole) && !actor.isAdmin() {
		return response.Forbidden("Only an admin can reset another admin's password")
	}
	hash, err := security.HashPassword(password)
	if err != nil {
		return err
	}
	return s.repo.SetPassword(ctx, id, hash, actor.ID)
}

// ---- helpers ----

func (s *Service) normalize(ctx context.Context, ref *string, name string, mobile, email *string, username string,
	deptID *int64, gender, dob *string) (*fields, error) {
	f := &fields{
		ReferenceNumber: trimPtr(ref),
		Name:            strings.TrimSpace(name),
		Mobile:          trimPtr(mobile),
		Email:           trimPtr(email),
		Username:        strings.TrimSpace(username),
		DepartmentID:    deptID,
		Gender:          gender,
	}
	if f.Name == "" {
		return nil, response.BadRequest("Name is required")
	}
	if !usernameRe.MatchString(f.Username) {
		return nil, response.BadRequest("Username may contain only letters, digits, dot, underscore and hyphen")
	}
	if f.Mobile != nil && !mobileRe.MatchString(*f.Mobile) {
		return nil, response.BadRequest("Mobile must be a valid 10-digit number")
	}
	if dob != nil && *dob != "" {
		t, err := time.Parse("2006-01-02", *dob)
		if err != nil || t.After(time.Now()) {
			return nil, response.BadRequest("dob must be a past date in YYYY-MM-DD format")
		}
		f.DOB = &t
	}
	if deptID != nil {
		ok, err := s.repo.DepartmentExists(ctx, *deptID)
		if err != nil {
			return nil, err
		}
		if !ok {
			return nil, response.BadRequest("department_id does not exist")
		}
	}
	return f, nil
}

func (s *Service) validateRoles(ctx context.Context, ids []int64, actor Actor) error {
	ids = slices.Compact(slices.Sorted(slices.Values(ids)))
	n, err := s.repo.CountActiveRoles(ctx, ids)
	if err != nil {
		return err
	}
	if n != len(ids) {
		return response.BadRequest("One or more role_ids are invalid")
	}
	if !actor.isAdmin() {
		// Non-admins (e.g. an HOD with user.create) must never be able to mint admins.
		includesAdmin, err := s.repo.IncludesRole(ctx, ids, rbac.AdminRole)
		if err != nil {
			return err
		}
		if includesAdmin {
			return response.Forbidden("Only an admin can assign the admin role")
		}
	}
	return nil
}

func mapWriteErr(err error) error {
	switch dbutil.UniqueViolation(err) {
	case "":
		return err
	case "ux_users_username":
		return response.Conflict("Username is already taken")
	case "ux_users_email":
		return response.Conflict("Email is already in use")
	case "ux_users_reference_number":
		return response.Conflict("Reference number is already in use")
	default:
		return response.Conflict("A record with the same unique value already exists")
	}
}

func hasRole(u *User, slug string) bool {
	return slices.ContainsFunc(u.Roles, func(r RoleRef) bool { return r.Slug == slug })
}

func trimPtr(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	if t == "" {
		return nil
	}
	return &t
}
