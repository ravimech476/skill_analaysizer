// Package actor describes the logged-in user performing a request.
package actor

import (
	"slices"

	"github.com/gin-gonic/gin"
)

type Actor struct {
	ID    int64
	Roles []string
}

// Has reports whether the actor holds any of the roles.
func (a Actor) Has(roles ...string) bool {
	for _, r := range roles {
		if slices.Contains(a.Roles, r) {
			return true
		}
	}
	return false
}

func (a Actor) IsAdmin() bool { return a.Has("admin") }

// Keys shared with middleware.Auth.
const (
	CtxUserID = "auth.user_id"
	CtxRoles  = "auth.roles"
)

func From(c *gin.Context) Actor {
	id, _ := c.Get(CtxUserID)
	roles, _ := c.Get(CtxRoles)
	a := Actor{}
	a.ID, _ = id.(int64)
	a.Roles, _ = roles.([]string)
	return a
}
