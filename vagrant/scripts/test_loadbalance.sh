for i in $(seq 1 6); do
  curl -s http://localhost:18080/api/container-id | grep -o '"hostname":"[^"]*"'
done