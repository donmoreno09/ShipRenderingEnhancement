#include "ApiEndpoints.h"

namespace ApiEndpoints {
    QString BaseUrl = "http://localhost:3000";

    QString Vessels() { return BaseUrl + "/vessels"; }
}
