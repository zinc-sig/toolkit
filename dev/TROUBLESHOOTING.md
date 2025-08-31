# Troubleshooting Guide

## Quick Fixes

### Environment Won't Start
```bash
# Check Docker
docker info

# Check ports
lsof -i :8080,9000,9001

# Clean restart
./dev.sh clean
./dev.sh start
```

### Pipeline Hangs
```bash
# Check resource
./bin/fly -t dev check-resource -r pipeline/resource-name
./bin/fly -t dev resource-versions -r pipeline/resource-name

# Check build status
./bin/fly -t dev builds -j pipeline/job-name
```

### MinIO Connection Failed
```bash
# Get correct IP (DNS doesn't work!)
docker inspect toolkit-minio --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

# Use IP instead of hostname
# Wrong: http://toolkit-minio:9000
# Right: http://172.19.0.2:9000
```

## Common Issues

### 🔴 Issue: Services won't start

**Symptom:**
```
docker: Cannot connect to the Docker daemon
```

**Solution:**
1. Ensure Docker Desktop is running
2. Check Docker status: `docker info`
3. Restart Docker Desktop
4. Try again: `./dev.sh start`

---

### 🔴 Issue: Port already in use

**Symptom:**
```
bind: address already in use
```

**Solution:**
```bash
# Find what's using the ports
lsof -i :8080
lsof -i :9000
lsof -i :9001

# Kill the process or change ports in docker-compose.yml
```

---

### 🔴 Issue: "undefined vars" error

**Symptom:**
```
failed to interpolate task config: undefined vars: compiler_flags, language, output_binary
```

**Causes:** 
1. Parameter names are case-sensitive
2. Mock resources try to interpolate `(())` placeholders

**Solutions:**

1. Use correct parameter names:
```bash
# Wrong
fly -t dev execute -c task.yaml -v SOURCE_FILE=main.c

# Correct
fly -t dev execute -c task.yaml -v source_file=main.c
```

2. Store task YAMLs in MinIO instead of mock resources:
```bash
# Upload to MinIO
cd /home/system/workspace/stommydx/zinc-sig/toolkit
docker run --rm --network toolkit-dev-network -v $(pwd):/workspace --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc cp /workspace/compilation/gcc.yaml minio/task-inputs/gcc-v1.yaml"
```

3. Use `vars:` field for interpolation:
```yaml
- task: run-task
  file: task-yaml/gcc.yaml
  vars:
    source_file: submission/hello.c
    output_binary: hello
```

---

### 🔴 Issue: Binary not found in execution job

**Symptom:**
```
chmod: compilation-output/addition: No such file or directory
```

**Cause:** Artifacts not passed correctly between jobs

**Solution 1:** Combine tasks in single job
```yaml
jobs:
  - name: compile-and-test
    plan:
      - task: compile
        outputs: [{name: binary}]
      - task: test
        inputs: [{name: binary}]  # Uses output from compile
```

**Solution 2:** Use S3 resource for artifact passing
```yaml
- put: compilation-outputs
  params:
    file: compilation-output/*
    
- get: compilation-outputs
  passed: [compile-job]
```

---

### 🔴 Issue: Ghost upload provider error

**Symptom:**
```
Error: failed to configure upload provider: minio: endpoint is required
```

**Cause:** Ghost not receiving MinIO configuration

**Solution:** Use `GHOST_UPLOAD_CONFIG_*` environment variables:
```yaml
params:
  # Must use GHOST_UPLOAD_CONFIG_* prefix
  GHOST_UPLOAD_CONFIG_ENDPOINT: http://172.19.0.2:9000
  GHOST_UPLOAD_CONFIG_ACCESS_KEY: minioadmin
  GHOST_UPLOAD_CONFIG_SECRET_KEY: minioadmin
  GHOST_UPLOAD_CONFIG_BUCKET: task-outputs
```

---

### 🔴 Issue: Pipeline file not found

**Symptom:**
```
fatal: '/home/system/workspace/toolkit' does not appear to be a git repository
```

**Cause:** Local file paths don't work in Concourse workers

**Solution:** Use inline task configurations
```yaml
- task: my-task
  config:  # Inline instead of file: reference
    platform: linux
    image_resource: ...
    run: ...
```

---

### 🔴 Issue: Mock resource keeps resetting

**Symptom:** Data doesn't persist between job runs

**Cause:** Mock resources are stateless

**Solution:** 
- Use mock resources only for input data
- Use S3/MinIO for data that needs to persist
- Combine related tasks in single job

---

### 🔴 Issue: Fly target not found

**Symptom:**
```
error: unknown target: dev
```

**Solution:**
```bash
# Re-login to Concourse
./bin/fly -t dev login -c http://localhost:8080 -u dev -p dev
```

---

### 🔴 Issue: Pipeline doesn't trigger

**Symptom:** Pipeline created but jobs don't run

**Solution:**
```bash
# Check if pipeline is paused
./bin/fly -t dev pipelines

# Unpause if needed
./bin/fly -t dev unpause-pipeline -p pipeline-name

# Manually trigger
./bin/fly -t dev trigger-job -j pipeline-name/job-name
```

---

### 🔴 Issue: Can't access MinIO

**Symptom:** Connection refused to localhost:9000

**Solution:**
1. Check if MinIO is running: `docker ps | grep minio`
2. Check logs: `docker logs toolkit-minio`
3. Restart services: `./dev.sh stop && ./dev.sh start`

---

### 🔴 Issue: Compilation works but execution fails

**Symptom:** Binary compiles but won't run

**Possible Causes:**
1. Binary not marked executable: Add `chmod +x binary`
2. Wrong path: Check actual location with `ls -la`
3. Architecture mismatch: Ensure using linux/amd64

**Solution:**
```yaml
run:
  path: sh
  args:
    - -c
    - |
      chmod +x compilation-output/program
      ./compilation-output/program
```

---

## Debugging Commands

### View container logs
```bash
docker logs toolkit-concourse
docker logs toolkit-minio
docker logs toolkit-concourse-db
```

### Access running container
```bash
docker exec -it toolkit-concourse bash
```

### Check resource versions
```bash
./bin/fly -t dev check-resource -r pipeline-name/resource-name
```

### Get pipeline configuration
```bash
./bin/fly -t dev get-pipeline -p pipeline-name
```

### Watch job in real-time
```bash
./bin/fly -t dev watch -j pipeline-name/job-name
```

### Intercept running task
```bash
./bin/fly -t dev intercept -j pipeline-name/job-name
```

### Download build artifacts
```bash
./bin/fly -t dev execute -c task.yaml -o output-name=./local-dir
```

## Network Issues

### Container can't reach other container (DNS Issues)

**Problem:** Concourse workers with containerd runtime cannot resolve Docker container hostnames

**Solution:** Always use IP addresses instead of hostnames
```yaml
# Wrong - DNS doesn't work
endpoint: http://toolkit-minio:9000

# Correct - Use IP address
endpoint: http://172.19.0.2:9000
```

**Get container IP:**
```bash
docker inspect toolkit-minio --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```

### Host can't reach services

**Check:**
1. Firewall settings
2. Docker network: `docker network ls`
3. Port forwarding: `docker ps`

## Performance Issues

### Slow pipeline execution

**Causes:**
1. Large Docker images being pulled
2. Insufficient resources

**Solutions:**
1. Use smaller base images (alpine versions)
2. Increase Docker memory allocation
3. Use image caching

### Out of disk space

**Solution:**
```bash
# Clean up Docker
docker system prune -a

# Remove unused volumes
docker volume prune

# Check disk usage
docker system df
```

## Reset Everything

If all else fails:

```bash
# Complete reset
./dev.sh clean
docker system prune -a --volumes
rm -rf bin/fly

# Fresh start
./dev.sh start
```

### 🔴 Issue: "latest version of resource not found" (S3 Resource)

**Symptom:** Pipeline hangs, S3 resource can't find files

**Diagnosis:**
```bash
# Check resource
./bin/fly -t dev check-resource -r pipeline/resource-name

# List versions
./bin/fly -t dev resource-versions -r pipeline/resource-name

# Verify file in MinIO
docker run --rm --network toolkit-dev-network --entrypoint sh \
  minio/mc:latest -c "mc alias set minio http://172.19.0.2:9000 minioadmin minioadmin && \
  mc ls minio/task-inputs/"
```

**Solutions:**
1. Ensure file matches regexp pattern exactly (S3 resource anchors on both ends)
2. Use versioned naming: `gcc-v1.yaml` matches `gcc-(.*).yaml`
3. Upload file to MinIO first

### 🔴 Issue: GitHub Release Download Hangs

**Symptom:** Ghost resource fetch takes forever

**Root Cause:** GitHub API rate limiting or network issues

**Solutions:**
1. Be patient (can take 2-5 minutes)
2. Ensure correct configuration:
```yaml
- name: ghost
  type: github-release
  source:
    owner: zinc-sig
    repository: ghost
    release: true       # Must have
    pre_release: false  # Must have
```

## Getting More Help

### Collect debugging information
```bash
# Save this output when reporting issues
./dev.sh status > debug.txt
docker ps >> debug.txt
docker logs toolkit-concourse --tail 50 >> debug.txt
./bin/fly -t dev pipelines >> debug.txt
```

### Check logs
- Concourse logs: `docker logs toolkit-concourse`
- Worker logs: Look for "selected worker" in job output
- Task logs: `./bin/fly -t dev watch -j pipeline/job`

### Useful resources
- Concourse docs: https://concourse-ci.org/docs.html
- Ghost repo: https://github.com/zinc-sig/ghost
- Docker docs: https://docs.docker.com/

## Prevention Tips

1. **Always start simple** - Test with echo tasks first
2. **Check examples** - Working examples in `examples/`
3. **Read LESSONS_LEARNED.md** - Learn from past issues
4. **Version control** - Commit working configurations
5. **Test incrementally** - Add complexity gradually

---
*Remember: Most issues are related to resource passing, parameter naming, or file paths!*