package request

import (
	"strconv"

	"github.com/gin-gonic/gin"

	"skills-analyzer/internal/pkg/response"
)

// Bind decodes + validates the JSON body; on failure it writes a 400 and returns ok=false.
func Bind[T any](c *gin.Context) (*T, bool) {
	var req T
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, response.BadRequest("Invalid request", err.Error()))
		return nil, false
	}
	return &req, true
}

// ID parses a positive int64 path param; on failure it writes a 400 and returns ok=false.
func ID(c *gin.Context, name string) (int64, bool) {
	id, err := strconv.ParseInt(c.Param(name), 10, 64)
	if err != nil || id <= 0 {
		response.Error(c, response.BadRequest("Invalid "+name))
		return 0, false
	}
	return id, true
}

// QueryInt64 returns an optional int64 query param (nil when absent or invalid).
func QueryInt64(c *gin.Context, name string) *int64 {
	v, err := strconv.ParseInt(c.Query(name), 10, 64)
	if err != nil {
		return nil
	}
	return &v
}
