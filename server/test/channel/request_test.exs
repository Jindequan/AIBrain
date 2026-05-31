defmodule AIBrain.Channel.RequestTest do
  use ExUnit.Case, async: true

  alias AIBrain.Channel.Request

  test "normalize/1 preserves structured capability_status requests" do
    raw = %{"type" => "capability_status", "session_id" => "s1", "channel" => "cli"}

    assert {:ok,
            %{
              type: :capability_status,
              session_id: "s1",
              channel: :cli
            }} = Request.normalize(raw)
  end

  test "normalize/1 accepts versioned capability status query envelopes" do
    raw = %{
      "schema_version" => 1,
      "query_kind" => "capability_status",
      "channel" => "cli",
      "payload" => %{"session_id" => "s2"}
    }

    assert {:ok,
            %{
              type: :capability_status,
              channel: :cli,
              session_id: "s2",
              query_kind: :capability_status,
              schema_version: 1
            }} = Request.normalize(raw)
  end

  test "normalize/1 accepts versioned text command directives for capability status" do
    raw = %{
      "schema_version" => 1,
      "directive_kind" => "text_command",
      "channel" => "cli",
      "payload" => %{
        "command" => "/capabilities",
        "session_id" => "s3"
      }
    }

    assert {:ok,
            %{
              type: :capability_status,
              channel: :cli,
              session_id: "s3",
              directive_kind: :text_command,
              schema_version: 1,
              original_type: :directive,
              content: "/capabilities"
            }} = Request.normalize(raw)
  end

  test "normalize/1 converts message commands into capability_status requests" do
    raw = %{
      "type" => "message",
      "content" => "/capabilities",
      "session_id" => "s1",
      "channel" => "cli"
    }

    assert {:ok,
            %{
              type: :capability_status,
              session_id: "s1",
              channel: :cli,
              content: "/capabilities",
              original_type: :message
            }} = Request.normalize(raw)
  end

  test "normalize/1 rejects unsupported inbound messages" do
    assert {:error, :unsupported_request} =
             Request.normalize(%{"type" => "message", "content" => "/unknown"})
  end

  test "normalize/1 preserves structured operator diagnostic requests" do
    raw = %{
      "type" => "operator_diagnostic",
      "diagnostic_type" => "permission_denial",
      "payload" => %{"tool_name" => "bash", "reason" => "plan_mode", "mode" => "plan"},
      "channel" => "cli"
    }

    assert {:ok,
            %{
              type: :operator_diagnostic,
              diagnostic_type: :permission_denial,
              payload: %{"tool_name" => "bash", "reason" => "plan_mode", "mode" => "plan"},
              channel: :cli
            }} = Request.normalize(raw)
  end

  test "normalize/1 accepts versioned operator diagnostic query envelopes" do
    raw = %{
      "schema_version" => 1,
      "query_kind" => "operator_diagnostic",
      "channel" => "cli",
      "payload" => %{
        "diagnostic_type" => "permission_denial",
        "payload" => %{"tool_name" => "bash", "reason" => "plan_mode", "mode" => "plan"}
      }
    }

    assert {:ok,
            %{
              type: :operator_diagnostic,
              query_kind: :operator_diagnostic,
              schema_version: 1,
              diagnostic_type: :permission_denial,
              channel: :cli,
              payload: %{"tool_name" => "bash", "reason" => "plan_mode", "mode" => "plan"}
            }} = Request.normalize(raw)
  end

  test "normalize/1 accepts versioned diagnostics summary query envelopes" do
    raw = %{
      "schema_version" => 1,
      "query_kind" => "diagnostics_summary",
      "channel" => "cli",
      "payload" => %{
        "export" => %{
          "capability_summary" => %{
            "enabled" => [%{"name" => "review-kit", "source" => "user"}],
            "rejected" => []
          }
        }
      }
    }

    assert {:ok,
            %{
              type: :diagnostics_summary,
              query_kind: :diagnostics_summary,
              schema_version: 1,
              channel: :cli,
              export: %{
                "capability_summary" => %{
                  "enabled" => [%{"name" => "review-kit", "source" => "user"}],
                  "rejected" => []
                }
              }
            }} = Request.normalize(raw)
  end

  test "normalize/1 accepts versioned capability rejections query envelopes" do
    raw = %{
      "schema_version" => 1,
      "query_kind" => "capability_rejections",
      "channel" => "cli",
      "payload" => %{
        "export" => %{
          "capability_summary" => %{
            "enabled" => [],
            "rejected" => [
              %{
                "name" => "workspace-kit",
                "source" => "project_local",
                "reason" => "project_local_disabled",
                "explanation" => "Project-local capabilities require explicit workspace trust."
              }
            ]
          }
        }
      }
    }

    assert {:ok,
            %{
              type: :capability_rejections,
              query_kind: :capability_rejections,
              schema_version: 1,
              channel: :cli,
              export: %{
                "capability_summary" => %{
                  "enabled" => [],
                  "rejected" => [
                    %{
                      "name" => "workspace-kit",
                      "source" => "project_local",
                      "reason" => "project_local_disabled",
                      "explanation" =>
                        "Project-local capabilities require explicit workspace trust."
                    }
                  ]
                }
              }
            }} = Request.normalize(raw)
  end

  test "normalize/1 accepts versioned permission diagnostics summary query envelopes" do
    raw = %{
      "schema_version" => 1,
      "query_kind" => "permission_diagnostics_summary",
      "channel" => "cli",
      "payload" => %{
        "export" => %{
          "operator_diagnostics" => %{
            "permissions" => %{
              "counts" => %{"approved" => 1, "denied" => 1},
              "denials" => [
                %{"tool_name" => "write_echo", "reason" => "plan_mode", "mode" => "plan"}
              ]
            }
          }
        }
      }
    }

    assert {:ok,
            %{
              type: :permission_diagnostics_summary,
              query_kind: :permission_diagnostics_summary,
              schema_version: 1,
              channel: :cli,
              export: %{
                "operator_diagnostics" => %{
                  "permissions" => %{
                    "counts" => %{"approved" => 1, "denied" => 1},
                    "denials" => [
                      %{"tool_name" => "write_echo", "reason" => "plan_mode", "mode" => "plan"}
                    ]
                  }
                }
              }
            }} = Request.normalize(raw)
  end

  test "normalize/1 accepts versioned sandbox diagnostics summary query envelopes" do
    raw = %{
      "schema_version" => 1,
      "query_kind" => "sandbox_diagnostics_summary",
      "channel" => "cli",
      "payload" => %{
        "export" => %{
          "operator_diagnostics" => %{
            "sandbox" => %{
              "counts" => %{"allowed" => 1, "blocked" => 1},
              "blocked" => [
                %{"tool_use_id" => "s1", "operation" => "workspace_write", "result" => "blocked"}
              ]
            }
          }
        }
      }
    }

    assert {:ok,
            %{
              type: :sandbox_diagnostics_summary,
              query_kind: :sandbox_diagnostics_summary,
              schema_version: 1,
              channel: :cli
            }} = Request.normalize(raw)
  end

  test "normalize/1 accepts versioned sandbox feedback entries query envelopes" do
    raw = %{
      "schema_version" => 1,
      "query_kind" => "sandbox_feedback_entries",
      "channel" => "cli",
      "payload" => %{
        "export" => %{
          "operator_diagnostics" => %{
            "sandbox" => %{
              "counts" => %{"allowed" => 0, "blocked" => 1},
              "blocked" => [
                %{"tool_use_id" => "s1", "operation" => "workspace_write", "result" => "blocked"}
              ]
            }
          }
        }
      }
    }

    assert {:ok,
            %{
              type: :sandbox_feedback_entries,
              query_kind: :sandbox_feedback_entries,
              schema_version: 1,
              channel: :cli
            }} = Request.normalize(raw)
  end

  test "normalize/1 converts denied permission_checked events into operator diagnostics" do
    raw = %{
      "type" => "permission_checked",
      "tool_name" => "bash",
      "decision" => "denied",
      "reason" => "plan_mode",
      "mode" => "plan",
      "channel" => "cli"
    }

    assert {:ok,
            %{
              type: :operator_diagnostic,
              diagnostic_type: :permission_denial,
              channel: :cli,
              payload: %{
                "tool_name" => "bash",
                "decision" => "denied",
                "reason" => "plan_mode",
                "mode" => "plan",
                "channel" => "cli"
              }
            }} = Request.normalize(raw)
  end

  test "normalize/1 converts sandbox feedback into operator diagnostics" do
    raw = %{
      "type" => "sandbox_feedback",
      "result" => "blocked",
      "operation" => "workspace_write",
      "detail" => "Writes outside the allowed workspace are blocked.",
      "channel" => "cli"
    }

    assert {:ok,
            %{
              type: :operator_diagnostic,
              diagnostic_type: :sandbox_feedback,
              channel: :cli,
              payload: %{
                "type" => "sandbox_feedback",
                "result" => "blocked",
                "operation" => "workspace_write",
                "detail" => "Writes outside the allowed workspace are blocked.",
                "channel" => "cli"
              }
            }} = Request.normalize(raw)
  end

  test "normalize/1 rejects unsupported query schema versions" do
    raw = %{"schema_version" => 2, "query_kind" => "capability_status", "payload" => %{}}
    assert {:error, :unsupported_request} = Request.normalize(raw)
  end
end
