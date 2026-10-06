package pagination

import (
	"strconv"

	"github.com/gin-gonic/gin"
)

type Params struct {
	Page     int
	PageSize int
}

func (p Params) Offset() int { return (p.Page - 1) * p.PageSize }

// FromQuery reads ?page=&page_size= (defaults 1 / 20, page_size capped at 200).
func FromQuery(c *gin.Context) Params {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	size, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if size < 1 {
		size = 20
	}
	if size > 200 {
		size = 200
	}
	return Params{Page: page, PageSize: size}
}
