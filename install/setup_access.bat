@SET admin=admin
ntrights -u %admin% +r SeAssignPrimaryTokenPrivilege
ntrights -u %admin% +r SeTcbPrivilege
ntrights -u %admin% +r SeIncreaseQuotaPrivilege
@rem BUILTIN\Users
icacls .. /remove:g "*S-1-5-32-545"
