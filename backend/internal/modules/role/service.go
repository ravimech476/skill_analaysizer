package role

import (
	"context"
	"regexp"
	"slices"
	"strings"

	"skills-analyzer/internal/pkg/dbutil"
	"skills-analyzer/internal/pkg/response"
	"skills-analyzer/internal/rbac"
)

type CreateRequest struct {
	Name          string  `json:"name" binding:"required,max=100"`
	Slug          string  `json:"slug" binding:"omitempty,max=100"`
	Description   *string `json:"description"`
	PermissionIDs []int64 `json:"permission_ids"`
}

type UpdateRequest struct {
	Name        string  `json:"name" binding:"required,max=100"`
	Description *string `json:"description"`
}

type SetPermissionsRequest struct {
	PermissionIDs []int64 `json:"permission_ids" binding:"required"`
}

type Service struct {
	repo  *Repository
	cache *rbac.Cache
}

func NewService(repo *Repository, cache *rbac.Cache) *Service {
	return &Service{repo: repo, cache: cache}
}

var slugRe = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(s string) string {
	return strings.Trim(slugRe.ReplaceAllString(strings.ToLower(s), "_"), "_")
}

func (s *Service) List(ctx context.Context, includeInactive bool) ([]*Role, error) {
	return s.repo.List(ctx, includeInactive)
}

func (s *Service) Get(ctx context.Context, id int64) (*Role, error) {
	r, err := s.repo.Get(ctx, id)
	if dbutil.IsNoRows(err) {
		return nil, response.NotFound("Role not found")
	}
	return r, err
}

func (s *Service) Create(ctx context.Context, req CreateRequest, actor int64) (*Role, error) {
	slug := slugify(req.Slug)
	if slug == "" {
		slug = slugify(req.Name)
	}
	if slug == "" {
		return nil, response.BadRequest("Role name must contain letters or digits")
	}
	if err := s.validatePermissions(ctx, req.PermissionIDs); err != nil {
		return nil, err
	}
	id, err := s.repo.Create(ctx, strings.TrimSpace(req.Name), slug, req.Description, actor)
	if dbutil.UniqueViolation(err) != "" {
		return nil, response.Conflict("A role with slug '" + slug + "' already exists")
	}
	if err != nil {
		return nil, err
	}
	if len(req.PermissionIDs) > 0 {
		if err := s.repo.SetPermissions(ctx, id, req.PermissionIDs, actor); err != nil {
			return nil, err
		}
		s.cache.Invalidate()
	}
	return s.repo.Get(ctx, id)
}

func (s *Service) Update(ctx context.Context, id int64, req UpdateRequest, actor int64) (*Role, error) {
	if _, err := s.Get(ctx, id); err != nil {
		return nil, err
	}
	if err := s.repo.Update(ctx, id, strings.TrimSpace(req.Name), req.Description, actor); err != nil {
		return nil, err
	}
	return s.repo.Get(ctx, id)
}

func (s *Service) Delete(ctx context.Context, id int64, actor int64) error {
	r, err := s.Get(ctx, id)
	if err != nil {
		return err
	}
	if r.IsSystem {
		return response.Conflict("System roles cannot be deleted")
	}
	if r.UserCount > 0 {
		return response.Conflict("Role is assigned to users; remove it from them first")
	}
	if err := s.repo.Deactivate(ctx, id, actor); err != nil {
		return err
	}
	s.cache.Invalidate()
	return nil
}

func (s *Service) SetPermissions(ctx context.Context, id int64, req SetPermissionsRequest, actor int64) (*Role, error) {
	r, err := s.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	if r.Slug == rbac.AdminRole {
		return nil, response.Conflict("Admin always has every permission")
	}
	if err := s.validatePermissions(ctx, req.PermissionIDs); err != nil {
		return nil, err
	}
	if err := s.repo.SetPermissions(ctx, id, req.PermissionIDs, actor); err != nil {
		return nil, err
	}
	s.cache.Invalidate()
	return s.repo.Get(ctx, id)
}

func (s *Service) validatePermissions(ctx context.Context, ids []int64) error {
	ids = slices.Compact(slices.Sorted(slices.Values(ids)))
	if len(ids) == 0 {
		return nil
	}
	n, err := s.repo.CountActivePermissions(ctx, ids)
	if err != nil {
		return err
	}
	if n != len(ids) {
		return response.BadRequest("One or more permission_ids are invalid")
	}
	return nil
}
