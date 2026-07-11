{{- define "task-tracker.fullname" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "task-tracker.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
