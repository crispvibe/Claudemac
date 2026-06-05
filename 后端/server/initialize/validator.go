package initialize

import "heyu/server/utils"

func init() {
	_ = utils.RegisterRule("PageVerify",
		utils.Rules{
			"Page":     {utils.NotEmpty()},
			"PageSize": {utils.NotEmpty()},
		},
	)
	_ = utils.RegisterRule("IdVerify",
		utils.Rules{
			"Id": {utils.NotEmpty()},
		},
	)
	_ = utils.RegisterRule("RoleIdVerify",
		utils.Rules{
			"RoleID": {utils.NotEmpty()},
		},
	)
}
